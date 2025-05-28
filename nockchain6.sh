#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

### CONFIG
REPO_URL="https://github.com/zorp-corp/nockchain"
PROJECT_DIR="$HOME/nockchain"
PUBKEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"
ENV_FILE="$PROJECT_DIR/.env"
MAKEFILE="$PROJECT_DIR/Makefile"
TMUX_SESSION="nock-miner"
ASSETS_DIR="$PROJECT_DIR/assets"
LOG_FILE="$PROJECT_DIR/miner.log"
JAM_FILES=(wal.jam miner.jam dumb.jam)

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
err() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }

echo ""
log "[!] Purging all files in $PROJECT_DIR except this script..."
mkdir -p "$PROJECT_DIR"
shopt -s extglob
cd "$PROJECT_DIR"
rm -rf !(nockchain_setup.sh) || true  # Adjust script name if needed
sleep 5
log "[✔] Directory cleaned."
echo ""

log "[+] Nockchain MainNet Bootstrap Starting..."
log "-------------------------------------------"

### 1. Rust Toolchain
log "[1/9] Installing Rust toolchain..."
if ! command -v cargo &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
fi
log "Rust version: $(rustc --version)"

### 2. System Dependencies
log "[2/9] Installing system dependencies..."
sudo apt update
sudo apt install -y git make build-essential clang llvm-dev libclang-dev tmux mailutils pkg-config libssl-dev

### 3. Clone or update repo
log "[3/9] Cloning or updating nockchain repo..."
if [ ! -d "$PROJECT_DIR/.git" ]; then
  git clone --depth 1 --branch master "$REPO_URL" "$PROJECT_DIR"
else
  cd "$PROJECT_DIR"
  git reset --hard HEAD
  git pull origin master
fi
cd "$PROJECT_DIR"
git status --short

### 4. Verify asset files
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
  err "One or more required .jam files are missing."
  exit 1
fi

### 5. Create or update .env with pubkey
log "[5/9] Writing .env file with mining pubkey..."
cp -f .env_example .env
sed -i "s|^MINING_PUBKEY=.*|MINING_PUBKEY=$PUBKEY|" "$ENV_FILE"
grep "MINING_PUBKEY" "$ENV_FILE"

### 6. Patch Makefile with pubkey
log "[6/9] Patching Makefile with pubkey..."
if grep -q "^export MINING_PUBKEY" "$MAKEFILE"; then
  sed -i "s|^export MINING_PUBKEY.*|export MINING_PUBKEY := $PUBKEY|" "$MAKEFILE"
else
  echo "export MINING_PUBKEY := $PUBKEY" >> "$MAKEFILE"
fi
grep "MINING_PUBKEY" "$MAKEFILE"

### 7. Build everything
log "[7/9] Building Nockchain..."
make install-hoonc
make build
make install-nockchain
make install-nockchain-wallet
make install-nockchain-miner
make install-nockchain-verifier
log "[✔] Build complete."

### 8. Clean old data & logs
log "[8/9] Cleaning old data directory and miner logs..."
rm -rf "$PROJECT_DIR/.data.nockchain"
rm -f "$LOG_FILE"

### 9. Launch miner in tmux with pubkey
log "[9/9] Launching miner in tmux session $TMUX_SESSION..."
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
tmux new-session -d -s "$TMUX_SESSION" \
  "cd $PROJECT_DIR && ./target/release/nockchain --mine --mining-pubkey $PUBKEY | tee -a $LOG_FILE"

sleep 30

# --- Test miner startup ---
log "[*] Testing miner startup and log for mining activity..."
if ! pgrep -f nockchain >/dev/null; then
  err "Miner process not running"
  exit 1
fi

if grep -q "block by-height" "$LOG_FILE"; then
  log "Mining activity detected in logs."
else
  err "No mining activity detected in logs."
  exit 1
fi

log "✅ Nockchain miner launched and running successfully."
echo "   - To view logs: tmux attach -t $TMUX_SESSION"
echo "   - Wallet pubkey used: $PUBKEY"
