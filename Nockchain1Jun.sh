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
log() { echo -e "\033[1;32m[\u2714]\033[0m $1"; }
err() { echo -e "\033[1;31m[\u2718]\033[0m $1" >&2; }

# Choose terminal multiplexer
SESSION_TYPE="tmux"

# Install dependencies
log "Installing dependencies..."
sudo apt update
sudo apt install -y git curl make tmux screen build-essential clang llvm-dev libclang-dev tree

# Install Rust if not present
if ! command -v cargo >/dev/null 2>&1; then
  log "Installing Rust toolchain..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
fi

# Clone or update repo
if [ -d "$REPO_DIR/.git" ]; then
  log "Updating existing Nockchain repo..."
  git -C "$REPO_DIR" reset --hard HEAD
  git -C "$REPO_DIR" pull origin master
else
  log "Cloning Nockchain repo..."
  git clone --depth 1 --branch master "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

# Generate kernel assets
log "Creating kernel asset files..."
mkdir -p "$ASSETS_DIR"
echo '(+ [1 2 3 4])' > "$ASSETS_DIR/wal.jam"
echo '(add 1 2)' > "$ASSETS_DIR/miner.jam"
echo '(mul 3 7)' > "$ASSETS_DIR/dumb.jam"

# Build the project
log "Patching form.rs for debugging..."
FORM_FILE="crates/nockapp/src/kernel/form.rs"
sed -i '/panic!("Kernel setup failed: oneshot channel error");/i \
use std::time::{SystemTime, UNIX_EPOCH};\nuse log::{error, info};\nlet now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();\nerror!("[DEBUG] Kernel send error at time: {now}");\n' "$FORM_FILE"

log "Compiling Nockchain..."
cargo clean
cargo build --release

# Generate wallet key
if [ ! -f "$WALLET_FILE" ]; then
  log "Generating wallet key..."
  ./target/release/nockchain-wallet keygen > "$WALLET_FILE"
fi

# Extract pubkey
PUBKEY=$(grep -oP '"pubkey":\s*"\K[^"]+' "$WALLET_FILE")
log "Using pubkey: $PUBKEY"

# Generate .env
log "Creating .env..."
cat > "$ENV_FILE" <<EOF
RUST_LOG=debug,nockchain=debug,nockchain_libp2p_io=debug,libp2p=info
MINIMAL_LOG_FORMAT=true
MINING_PUBKEY=$PUBKEY
EOF

# Patch Makefile
log "Patching Makefile with pubkey..."
grep -q "^export MINING_PUBKEY" "$MAKEFILE" && \
  sed -i "s|^export MINING_PUBKEY.*|export MINING_PUBKEY ?= $PUBKEY|" "$MAKEFILE" || \
  echo "export MINING_PUBKEY ?= $PUBKEY" >> "$MAKEFILE"

# Check required ports
REQUIRED_PORTS=(3000 3001 3002 3003 3004 3005 3006)
log "Checking ports..."
for port in "${REQUIRED_PORTS[@]}"; do
  if ss -lntup | grep -q ":$port"; then
    err "Port $port is already in use."
    exit 1
  fi
  log "Port $port is free."
done

# Launch miner
log "Launching miner using $SESSION_TYPE..."
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
  tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
  tmux new-session -d -s "$SESSION_NAME" "cd $REPO_DIR && $CMD"
else
  screen -S "$SESSION_NAME" -dm bash -c "cd $REPO_DIR && $CMD"
fi

log "\u2705 Miner launched in $SESSION_TYPE session '$SESSION_NAME'"
echo "Attach with:  $SESSION_TYPE attach -t $SESSION_NAME"
echo "Public Key: $PUBKEY"
