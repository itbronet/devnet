#!/bin/bash

set -euo pipefail

# Configuration
REPO_URL="https://github.com/zorp-corp/nockchain.git"
REPO_DIR="$HOME/nockchain"
ASSETS_DIR="$REPO_DIR/assets"
TMUX_SESSION="nock-miner"
ENV_FILE="$PROJECT_DIR/.env"
MAKEFILE="$PROJECT_DIR/Makefile"
MINING_KEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R" 
REQUIRED_PORTS=(3006 30000)

# Logging function
log() {
  echo -e "\033[1;32m[✔]\033[0m $1"
}

err() {
  echo -e "\033[1;31m[✘]\033[0m $1" >&2
}

# 1. Install prerequisites
log "Checking system requirements..."
command -v git >/dev/null || { log "Installing Git..."; sudo apt-get install -y git; }
command -v tmux >/dev/null || { log "Installing tmux..."; sudo apt-get install -y tmux; }
command -v curl >/dev/null || sudo apt-get install -y curl
command -v cargo >/dev/null || { log "Installing Rust..."; curl https://sh.rustup.rs -sSf | sh -s -- -y; source "$HOME/.cargo/env"; }

# 2. Clone or update repo
if [ -d "$REPO_DIR/.git" ]; then
  log "Updating existing Nockchain repo..."
  git -C "$REPO_DIR" pull
else
  log "Cloning Nockchain repository..."
  git clone "$REPO_URL" "$REPO_DIR"
fi

# 3. Create required .jam kernel files
log "Creating dummy .jam kernel files..."
mkdir -p "$ASSETS_DIR"

create_jam() {
  local file="$1"
  local content="$2"
  if [ ! -f "$ASSETS_DIR/$file" ]; then
    echo "$content" > "$ASSETS_DIR/$file"
    log "Created $file"
  fi
}

create_jam "wal.jam" '(+ [1 2 3 4])'
create_jam "miner.jam" '(add 1 2)'
create_jam "dumb.jam" '(mul 3 7)'

# 4. Commit .jam files (optional)
if git -C "$REPO_DIR" check-ignore "$ASSETS_DIR/wal.jam" >/dev/null; then
  log "Removing .jam files from .gitignore..."
  sed -i '/assets\/.*\.jam/d' "$REPO_DIR/.gitignore"
fi

log "Adding .jam files to Git..."
git -C "$REPO_DIR" add assets/*.jam || true
git -C "$REPO_DIR" commit -m "Add dummy .jam kernel files" || true

# 5. Build the project
log "Building Nockchain..."
cd "$REPO_DIR"
cargo build --release
echo "[+] Nockchain MainNet Bootstrap Starting..."
echo "-------------------------------------------"


### 6. Install Rust Toolchain
echo "[1/7] Installing Rust toolchain..."
if ! command -v cargo &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  export PATH="$HOME/.cargo/bin:$PATH"
fi

### 7. Install System Dependencies
echo "[2/7] Installing system dependencies..."
sudo apt update && sudo apt install -y \
  git \
  make \
  build-essential \
  clang \
  llvm-dev \
  libclang-dev \
  tmux

### 8. Clone Repo & Pull Latest
echo "[3/7] Cloning or updating Nockchain repo..."
if [ ! -d "$PROJECT_DIR" ]; then
  git clone --depth 1 --branch master "$REPO_URL" "$PROJECT_DIR"
else
  cd "$PROJECT_DIR"
  git reset --hard HEAD && git pull origin master
fi
cd "$PROJECT_DIR"

### 9. Create or update .env
echo "[4/7] Setting pubkey in .env..."
cp -f .env_example .env
sed -i "s|^MINING_PUBKEY=.*|MINING_PUBKEY=$PUBKEY|" "$ENV_FILE"
grep "MINING_PUBKEY" "$ENV_FILE"

### 10. Update Makefile with pubkey (if line exists)
echo "[5/7] Patching Makefile with pubkey..."
if grep -q "^export MINING_PUBKEY" "$MAKEFILE"; then
  sed -i "s|^export MINING_PUBKEY.*|export MINING_PUBKEY := $PUBKEY|" "$MAKEFILE"
else
  echo "export MINING_PUBKEY := $PUBKEY" >> "$MAKEFILE"
fi
grep "MINING_PUBKEY" "$MAKEFILE"

### 11. Build Everything
echo "[6/7] Building Nockchain..."
make install-hoonc
make build
make install-nockchain
make install-nockchain-wallet

# 12. Validate binary
if [ ! -f "$REPO_DIR/target/release/nockchain" ]; then
  err "nockchain binary not found after build."
  exit 1
fi

# 13. Start miner in tmux
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  log "Miner session already running."
else
  log "Starting miner in tmux session '$TMUX_SESSION'..."
  tmux new-session -d -s "$TMUX_SESSION" "cd $REPO_DIR && ./target/release/nockchain --mine --mining-pubkey $MINING_KEY | tee -a miner.log"
fi

# 14. Port check
for port in "${REQUIRED_PORTS[@]}"; do
  if ! ss -lntup | grep -q ":$port"; then
    log "Port $port appears free (good)."
  else
    err "Port $port is in use. Check conflicts!"
  fi
  
### 8. Start Miner using CLI pubkey
echo "[8/8] Launching miner in tmux with your pubkey..."
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
tmux new-session -d -s "$TMUX_SESSION" "cd $PROJECT_DIR && nockchain --mining-pubkey $PUBKEY --mine | tee -a miner.log"

echo ""
echo "✅ Nockchain MainNet Miner launched successfully!"
echo "   - To view miner logs: tmux attach -t $TMUX_SESSION"
echo "   - Wallet PubKey (used + saved): $PUBKEY"
echo ""
