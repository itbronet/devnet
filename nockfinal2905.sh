#!/bin/bash
set -euo pipefail

# Config
REPO_URL="https://github.com/zorp-corp/nockchain.git"
REPO_DIR="$HOME/nockchain"
ASSETS_DIR="$REPO_DIR/assets"
TMUX_SESSION="nock-miner"
ENV_FILE="$REPO_DIR/.env"
MAKEFILE="$REPO_DIR/Makefile"
MINING_KEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"
REQUIRED_PORTS=(3000 3001 3002 3003 3004 3005 3006)

# Logging
log()   { echo -e "\033[1;32m[✔]\033[0m $1"; }
err()   { echo -e "\033[1;31m[✘]\033[0m $1" >&2; }

# 1. Install prerequisites
log "Installing system dependencies..."
sudo apt update
sudo apt install -y git tmux curl make build-essential clang llvm-dev libclang-dev

if ! command -v cargo >/dev/null 2>&1; then
  log "Installing Rust toolchain..."
  curl https://sh.rustup.rs -sSf | sh -s -- -y
  source "$HOME/.cargo/env"
fi

# 2. Clone or update repo
if [ -d "$REPO_DIR/.git" ]; then
  log "Updating existing repo..."
  git -C "$REPO_DIR" reset --hard HEAD
  git -C "$REPO_DIR" pull origin master
else
  log "Cloning repo..."
  git clone --depth 1 --branch master "$REPO_URL" "$REPO_DIR"
fi

# 3. Create dummy .jam kernel files
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

# 4. Optionally commit .jam files
if grep -q "assets/.*\.jam" "$REPO_DIR/.gitignore"; then
  log "Removing .jam files from .gitignore..."
  sed -i '/assets\/.*\.jam/d' "$REPO_DIR/.gitignore"
fi

git -C "$REPO_DIR" add assets/*.jam || true
git -C "$REPO_DIR" commit -m "Add dummy .jam kernel files" || true

# 5. Setup .env file
log "Configuring .env..."
if [ -f "$REPO_DIR/.env_example" ]; then
  cp -f "$REPO_DIR/.env_example" "$ENV_FILE"
  sed -i "s|^MINING_PUBKEY=.*|MINING_PUBKEY=$MINING_KEY|" "$ENV_FILE"
else
  log ".env_example not found, creating basic .env"
  echo "MINING_PUBKEY=$MINING_KEY" > "$ENV_FILE"
fi

# 6. Patch Makefile
log "Updating Makefile with mining key..."
if grep -q "^export MINING_PUBKEY" "$MAKEFILE"; then
  sed -i "s|^export MINING_PUBKEY.*|export MINING_PUBKEY := $MINING_KEY|" "$MAKEFILE"
else
  echo "export MINING_PUBKEY := $MINING_KEY" >> "$MAKEFILE"
fi

# 7. Build project
log "Building Nockchain..."
cd "$REPO_DIR"
make install-hoonc
make build
make install-nockchain
make install-nockchain-wallet
make install-nockchain-miner
make install-nockchain-verifier

if [ ! -f "$REPO_DIR/target/release/nockchain" ]; then
  err "nockchain binary not found after build."
  exit 1
fi

# 8. Check required ports
log "Checking required ports..."
for port in "${REQUIRED_PORTS[@]}"; do
  if ss -lntup | grep -q ":$port"; then
    err "Port $port is in use! Please free it before running miner."
    exit 1
  else
    log "Port $port is free."
  fi
done

# 9. Start miner in tmux
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  log "Miner session already running."
else
  log "Starting miner in tmux session '$TMUX_SESSION'..."
  tmux new-session -d -s "$TMUX_SESSION" "cd $REPO_DIR && RUST_LOG=info,nockchain=info,nockchain_libp2p_io=info,libp2p=info,libp2p_quic=info MINIMAL_LOG_FORMAT=true ./target/release/nockchain --mine --mining-pubkey $MINING_KEY \
    --peer /ip4/34.95.155.151/udp/3000/quic-v1 \
    --peer /ip4/34.18.98.38/udp/3000/quic-v1 \
    --peer /ip4/34.174.22.166/udp/3001/quic-v1 \
    --peer /ip4/65.109.156.172/udp/3002/quic-v1 \
    --peer /ip4/65.21.67.175/udp/3003/quic-v1 \
    --peer /ip4/65.109.156.108/udp/3004/quic-v1 \
    --peer /ip4/65.108.123.225/udp/3005/quic-v1 \
    --peer /ip4/95.216.102.60/udp/3006/quic-v1 \
    --peer /ip4/96.230.252.205/udp/3006/quic-v1 \
    --peer /ip4/94.205.40.29/udp/3005/quic-v1 \
    --peer /ip4/159.112.204.186/udp/3004/quic-v1 \
    --peer /ip4/217.14.223.78/udp/3003/quic-v1 | tee -a miner.log"
fi

echo ""
echo "✅ Nockchain MainNet Miner launched successfully!"
echo "   - To view logs: tmux attach -t $TMUX_SESSION"
echo "   - Wallet PubKey (used + saved): $MINING_KEY"
echo ""
