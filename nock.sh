#!/bin/bash

set -e

### CONFIG
REPO_URL="https://github.com/zorp-corp/nockchain"
PROJECT_DIR="$HOME/nockchain"
PUBKEY="3LJM1jSAYMfUHg31zMVTWnFsNTbGenRZwVZgJzArfE2SyA2V4eJzz46vLguyK19RTbr5okQwG13RNXyjkPh2oWMeuXcDhGjyVPKbTEv9dDRtx742B53YZqvpeHpbASDRWa8P"
LEADER_PORT=3005
FOLLOWER_PORT=3006
LEADER_SOCK="leader.sock"
FOLLOWER_SOCK="follower.sock"
LEADER_DATA=".data.leader"
FOLLOWER_DATA=".data.follower"

echo ""
echo "[+] Nockchain DevNet Bootstrap Starting..."
echo "-------------------------------------------"

### 1. Install Rust Toolchain
echo "[1/6] Installing Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Add Rust to PATH
export PATH="$HOME/.cargo/bin:$PATH"

# Confirm cargo installed
if ! command -v cargo &> /dev/null; then
  echo "❌ Rust install failed. Aborting."
  exit 1
fi

### 2. Install dependencies
echo "[2/6] Installing dependencies..."
sudo apt update && sudo apt install -y \
  git \
  make \
  build-essential \
  clang \
  llvm-dev \
  libclang-dev \
  tmux

### 3. Clone repo
echo "[3/6] Cloning Nockchain repo..."
if [ ! -d "$PROJECT_DIR" ]; then
  git clone "$REPO_URL" "$PROJECT_DIR"
else
  echo "    Repo already exists. Pulling latest..."
  cd "$PROJECT_DIR"
  git pull origin main
fi
cd "$PROJECT_DIR"

### 4. Install Hoon Compiler (hoonc)
echo "[4/6] Installing Hoon Compiler (hoonc)..."
make install-hoonc

### 5. Build project
echo "[5/6] Building Nockchain project..."
make build-hoon-all
make build

### 5.5 Inject MINING_PUBKEY into Makefile
echo "[5.5] Forcing MINING_PUBKEY update into Makefile"
sed -i "s|^export MINING_PUBKEY.*|export MINING_PUBKEY := $PUBKEY|" "$PROJECT_DIR/Makefile"
grep "MINING_PUBKEY" "$PROJECT_DIR/Makefile"

### 6. Launch Leader & Follower in tmux
echo "[6/6] Launching Nockchain Leader & Follower in tmux..."

# Kill existing tmux sessions if they exist
tmux kill-session -t nock-leader 2>/dev/null || true
tmux kill-session -t nock-follower 2>/dev/null || true

# Clean sockets & data
rm -f "$PROJECT_DIR/$LEADER_SOCK" "$PROJECT_DIR/$FOLLOWER_SOCK"
rm -rf "$PROJECT_DIR/$LEADER_DATA" "$PROJECT_DIR/$FOLLOWER_DATA"

# Start Leader node
tmux new-session -d -s nock-leader "cd $PROJECT_DIR && make run-nockchain-leader"

# Wait for leader to initialize
sleep 6

# Start Follower node
tmux new-session -d -s nock-follower "cd $PROJECT_DIR && make run-nockchain-follower"

echo ""
echo "✅ Nockchain DevNet Miner launched successfully."
echo "   - tmux attach -t nock-leader"
echo "   - tmux attach -t nock-follower"
echo "   - Wallet PubKey: $PUBKEY"
echo ""
