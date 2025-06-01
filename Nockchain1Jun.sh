#!/bin/bash
set -euo pipefail

# Configuration
REPO_URL="https://github.com/zorp-corp/nockchain.git"
REPO_DIR="$HOME/nockchain"
ASSETS_DIR="$REPO_DIR/assets"
ENV_FILE="$REPO_DIR/.env"
MAKEFILE="$REPO_DIR/Makefile"
SESSION_NAME="nock-miner"
WALLET_FILE="$REPO_DIR/wallet_keys.txt"
MINER_BIN="$REPO_DIR/target/release/nockchain"

# Colors
log() { echo -e "\033[1;32m[✔]\033[0m $1"; }
err() { echo -e "\033[1;31m[✘]\033[0m $1" >&2; }

# Ask screen or tmux
read -rp "Use tmux or screen to run miner? [tmux/screen]: " SESSION_TYPE
SESSION_TYPE="${SESSION_TYPE:-tmux}"
if [[ "$SESSION_TYPE" != "tmux" && "$SESSION_TYPE" != "screen" ]]; then
  err "Invalid choice. Use 'tmux' or 'screen'."
  exit 1
fi

# Install dependencies
log "Installing dependencies..."
sudo apt update
sudo apt install -y git curl make tmux screen build-essential clang llvm-dev libclang-dev tree

if ! command -v cargo >/dev/null 2>&1; then
  log "Installing Rust toolchain..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
fi

# Clone or update the repo
if [ -d "$REPO_DIR/.git" ]; then
  log "Updating existing Nockchain repo..."
  git -C "$REPO_DIR" reset --hard HEAD
  git -C "$REPO_DIR" pull origin master
else
  log "Cloning Nockchain repo..."
  git clone --depth 1 --branch master "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

# Generate kernel files
log "Ensuring asset kernel files..."
mkdir -p "$ASSETS_DIR"
echo '(+ [1 2 3 4])' > "$ASSETS_DIR/wal.jam"
echo '(add 1 2)' > "$ASSETS_DIR/miner.jam"
echo '(mul 3 7)' > "$ASSETS_DIR/dumb.jam"

# Build the project
log "Building Nockchain..."
make install-hoonc
make build
make install-nockchain
make install-nockchain-wallet
make install-nockchain-miner
make install-nockchain-verifier

# Generate wallet key if not exist
if [ ! -f "$WALLET_FILE" ]; then
  log "Generating new wallet key..."
  ./target/release/nockchain-wallet keygen > "$WALLET_FILE"
fi

# Extract public key
PUBKEY=$(grep -oP '"pubkey":\s*"\K[^"]+' "$WALLET_FILE")
log "Using pubkey: $PUBKEY"

# Update .env
log "Updating .env..."
cat > "$ENV_FILE" <<EOF
RUST_LOG=info,nockchain=info,nockchain_libp2p_io=info,libp2p=info,libp2p_quic=info
MINIMAL_LOG_FORMAT=true
MINING_PUBKEY=$PUBKEY
EOF

# Patch Makefile
log "Patching Makefile..."
if grep -q "^export MINING_PUBKEY" "$MAKEFILE"; then
  sed -i "s|^export MINING_PUBKEY.*|export MINING_PUBKEY ?= $PUBKEY|" "$MAKEFILE"
else
  echo "export MINING_PUBKEY ?= $PUBKEY" >> "$MAKEFILE"
fi

# Ports to check
REQUIRED_PORTS=(3000 3001 3002 3003 3004 3005 3006)
log "Checking required ports..."
for port in "${REQUIRED_PORTS[@]}"; do
  if ss -lntup | grep -q ":$port"; then
    err "Port $port is in use!"
    exit 1
  else
    log "Port $port is available."
  fi
done

# Start miner
log "Launching Nockchain Miner with $SESSION_TYPE..."
CMD="$MINER_BIN --mine --mining-pubkey $PUBKEY \
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

if [ "$SESSION_TYPE" = "tmux" ]; then
  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux new-session -d -s "$SESSION_NAME" "cd $REPO_DIR && $CMD"
  fi
else
  if ! screen -list | grep -q "$SESSION_NAME"; then
    screen -S "$SESSION_NAME" -dm bash -c "cd $REPO_DIR && $CMD"
  fi
fi

log "✅ Nockchain miner is running in $SESSION_TYPE session '$SESSION_NAME'"
echo "   Attach with:  $SESSION_TYPE attach -t $SESSION_NAME"
echo "   PubKey: $PUBKEY"
