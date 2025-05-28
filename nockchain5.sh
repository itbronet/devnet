#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

REPO_URL="https://github.com/zorp-corp/nockchain"
PROJECT_DIR="$HOME/nockchain"
ENV_FILE="$PROJECT_DIR/.env"
MAKEFILE="$PROJECT_DIR/Makefile"
WALLET_DIR="$HOME/.nockchain-wallet"
TMUX_SESSION="nock-miner"
EMAIL="itbronet@gmail.com"
ASSETS_DIR="$PROJECT_DIR/assets"
LOG_FILE="$PROJECT_DIR/miner.log"
PUBKEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"

JAM_FILES=( wal.jam miner.jam dumb.jam )

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

err() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# --- Cleanup ---
log "[0/9] Cleaning $PROJECT_DIR (except this script)..."
if [ -d "$PROJECT_DIR" ]; then
  find "$PROJECT_DIR" -mindepth 1 ! -name "$(basename "$0")" -exec rm -rf {} +
else
  mkdir -p "$PROJECT_DIR"
fi
sleep 3
log "[✔] Cleanup done."

# --- Install Rust toolchain ---
log "[1/9] Installing Rust toolchain if missing..."
if ! command -v cargo &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
else
  log "Rust is already installed: $(rustc --version)"
fi

# --- Install system dependencies ---
log "[2/9] Installing system dependencies..."
sudo apt-get update

# Preseed postfix answers to skip interactive prompt
sudo debconf-set-selections <<EOF
postfix postfix/main_mailer_type select Internet Site
postfix postfix/mailname string $(hostname -f)
EOF

sudo apt-get install -y \
  git make build-essential clang llvm-dev libclang-dev tmux mailutils pkg-config libssl-dev

# --- Clone or update repo ---
if [ ! -d "$PROJECT_DIR/.git" ]; then
  log "[3/9] Cloning nockchain repo..."
  git clone "$REPO_URL" "$PROJECT_DIR"
else
  log "[3/9] Updating existing repo..."
  cd "$PROJECT_DIR"
  git fetch --all
  git reset --hard origin/master
fi

# --- Verify assets directory and files ---
log "[4/9] Verifying assets directory and jam files..."
mkdir -p "$ASSETS_DIR"

missing=0
for f in "${JAM_FILES[@]}"; do
  if [ ! -f "$ASSETS_DIR/$f" ]; then
    err "Missing asset file: $f in $ASSETS_DIR"
    missing=1
  else
    log "Found asset: $f"
  fi
done
if [ "$missing" -eq 1 ]; then
  err "Please add the missing .jam files to $ASSETS_DIR before proceeding."
  exit 1
fi

# --- Write .env file ---
log "[5/9] Writing .env file with mining pubkey..."
cp -f "$PROJECT_DIR/.env_example" "$ENV_FILE"
sed -i "s|^MINING_PUBKEY=.*|MINING_PUBKEY=$PUBKEY|" "$ENV_FILE"

# --- Patch Makefile ---
log "[6/9] Patching Makefile with mining pubkey..."
if grep -q "^export MINING_PUBKEY" "$MAKEFILE"; then
  sed -i "s|^export MINING_PUBKEY.*|export MINING_PUBKEY := $PUBKEY|" "$MAKEFILE"
else
  echo "export MINING_PUBKEY := $PUBKEY" >> "$MAKEFILE"
fi

# --- Build project ---
log "[7/9] Building nockchain project..."
cd "$PROJECT_DIR"
make install-hoonc
make build
make install-nockchain
make install-nockchain-wallet
make install-nockchain-miner
make install-nockchain-verifier
log "[✔] Build finished."

# --- Kill existing miner ---
log "[8/9] Killing existing miner and tmux sessions..."
pkill -f nockchain || true
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
sleep 2

# --- Launch miner in tmux ---
log "[9/9] Launching miner in tmux session '$TMUX_SESSION'..."
: > "$LOG_FILE"
tmux new-session -d -s "$TMUX_SESSION" \
  "cd $PROJECT_DIR && ./target/release/nockchain --mine --mining-pubkey $PUBKEY | tee -a $LOG_FILE"

sleep 30

# --- Test mining activity ---
log "[*] Testing mining activity in miner log..."
if ! pgrep -f nockchain >/dev/null; then
  err "Miner process not running"
  echo "Nockchain miner process not running after launch" | mail -s "Nockchain Miner Error" "$EMAIL"
  exit 1
fi

if grep -q "block by-height" "$LOG_FILE"; then
  log "Mining activity detected!"
  echo "Nockchain mining started successfully" | mail -s "Nockchain Miner Started" "$EMAIL"
else
  err "No mining activity detected in log"
  echo "Nockchain mining failed to start or no blocks found" | mail -s "Nockchain Miner Error" "$EMAIL"
  exit 1
fi

log "[✔] Setup and miner launch complete."
