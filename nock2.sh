#!/bin/bash

set -euo pipefail

### CONFIG
REPO_URL="https://github.com/zorp-corp/nockchain"
PROJECT_DIR="$HOME/nockchain"
PUBKEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"
ENV_FILE="$PROJECT_DIR/.env"
MAKEFILE="$PROJECT_DIR/Makefile"
TMUX_SESSION="nock-miner"

echo ""
echo "[!] Cleaning previous build artifacts (safe)..."
rm -rf "$PROJECT_DIR/target" "$PROJECT_DIR/.data.nockchain" "$PROJECT_DIR/miner.log" || echo "Nothing to clean"
echo "[✔] Clean complete."
echo ""

echo "[+] Nockchain MainNet Bootstrap Starting..."
echo "-------------------------------------------"

### 1. Install Rust Toolchain
echo "[1/8] Checking Rust toolchain..."
if ! command -v cargo &>/dev/null; then
  echo "→ Installing Rust via rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  export PATH="$HOME/.cargo/bin:$PATH"
else
  echo "✓ Rust already installed."
fi

### 2. Install System Dependencies
echo "[2/8] Installing system dependencies..."
sudo apt update && sudo apt install -y \
  git \
  make \
  build-essential \
  clang \
  llvm-dev \
  libclang-dev \
  tmux

### 3. Clone Repo or Pull Latest
echo "[3/8] Cloning or updating Nockchain repo..."
if [ ! -d "$PROJECT_DIR" ]; then
  git clone --depth 1 --branch master "$REPO_URL" "$PROJECT_DIR"
else
  cd "$PROJECT_DIR"
  git reset --hard HEAD && git pull origin master
fi
cd "$PROJECT_DIR"

### 4. Create or update .env
echo "[4/8] Configuring .env file..."
cp -f .env_example .env
sed -i "s|^MINING_PUBKEY=.*|MINING_PUBKEY=$PUBKEY|" "$ENV_FILE"
sed -i "s|^RUST_LOG=.*|RUST_LOG=info,nockchain=info,nockchain_libp2p_io=info,libp2p=info,libp2p_quic=info|" "$ENV_FILE"
grep -E "MINING_PUBKEY|RUST_LOG" "$ENV_FILE"

### 5. Update Makefile with pubkey
echo "[5/8] Ensuring Makefile has correct pubkey..."
if grep -q "^export MINING_PUBKEY" "$MAKEFILE"; then
  sed -i "s|^export MINING_PUBKEY.*|export MINING_PUBKEY := $PUBKEY|" "$MAKEFILE"
else
  echo "export MINING_PUBKEY := $PUBKEY" >> "$MAKEFILE"
fi
grep "MINING_PUBKEY" "$MAKEFILE"

### 6. Build All Binaries
echo "[6/8] Building Nockchain components..."
make install-hoonc
make build
make install-nockchain
make install-nockchain-wallet
make install-nockchain-miner
make install-nockchain-verifier

### 7. Confirm Rust bin is in PATH
echo "[7/8] Exporting Rust path to ensure binaries work..."
export PATH="$HOME/.cargo/bin:$PATH"

### 8. Start Miner in tmux
echo "[8/8] Launching miner in tmux session..."
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
tmux new-session -d -s "$TMUX_SESSION" "cd $PROJECT_DIR && nockchain-miner --mining-pubkey $PUBKEY | tee -a miner.log"

echo ""
echo "✅ Nockchain MainNet Miner launched successfully!"
echo "   - To view miner logs: tmux attach -t $TMUX_SESSION"
echo "   - Wallet PubKey used: $PUBKEY"
echo ""

send_email() {
  local subject="$1"
  local message="$2"
  echo -e "$message" | mail -s "$subject" itbronet@gmail.com
}

# Send success email
send_email "✅ Nockchain Miner Launched" "Miner started successfully on $(hostname).\nPubKey: $PUBKEY\nTime: $(date)"
trap 'send_email "❌ Nockchain Setup Failed" "The setup script encountered an error on $(hostname) at $(date). Please check the logs for details."' ERR

