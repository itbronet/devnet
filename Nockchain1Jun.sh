#!/bin/bash
set -euo pipefail

### CONFIG
REPO_URL="https://github.com/zorp-corp/nockchain"
PROJECT_DIR="$HOME/nockchain"
ASSETS_DIR="/root/assets"
BIN_DIR="$PROJECT_DIR/target/release"
ENV_FILE="$PROJECT_DIR/.env"
MAKEFILE="$PROJECT_DIR/Makefile"
TMUX_SESSION="nock-miner"

echo ""
echo "[+] Nockchain MainNet Bootstrap Starting..."
echo "-------------------------------------------"

### 1. Install Rust Toolchain
echo "[1/8] Installing Rust toolchain..."
if ! command -v cargo &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  export PATH="$HOME/.cargo/bin:$PATH"
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

### 3. Clone Repo & Pull Latest
echo "[3/8] Cloning or updating Nockchain repo..."
if [ ! -d "$PROJECT_DIR" ]; then
  git clone --depth 1 --branch master "$REPO_URL" "$PROJECT_DIR"
else
  cd "$PROJECT_DIR"
  git reset --hard HEAD && git pull origin master
fi

cd "$PROJECT_DIR"

### 4. Build Nockchain
echo "[4/8] Building Nockchain..."
make install-hoonc
make build
make install-nockchain
make install-nockchain-wallet

### 5. Generate Key and Assets
echo "[5/8] Generating new key and assets..."
mkdir -p "$ASSETS_DIR"

$BIN_DIR/nock keygen > "$ASSETS_DIR/key.jam" || { echo "❌ Failed to generate key"; exit 1; }
$BIN_DIR/nock wal "$ASSETS_DIR/key.jam" > "$ASSETS_DIR/wal.jam" || { echo "❌ Failed to generate wal.jam"; exit 1; }
$BIN_DIR/nock miner "$ASSETS_DIR/key.jam" > "$ASSETS_DIR/miner.jam" || { echo "❌ Failed to generate miner.jam"; exit 1; }
$BIN_DIR/nock dumb "$ASSETS_DIR/key.jam" > "$ASSETS_DIR/dumb.jam" || { echo "❌ Failed to generate dumb.jam"; exit 1; }

# Extract pubkey from wal.jam
PUBKEY=$(cat "$ASSETS_DIR/wal.jam" | grep '"pubkey"' | sed 's/.*"pubkey": "\(.*\)".*/\1/')
if [[ -z "$PUBKEY" ]]; then
  echo "❌ Failed to extract pubkey from wal.jam"
  exit 1
fi

echo "✅ Key and asset files created in $ASSETS_DIR"
echo "   ➤ PUBKEY: $PUBKEY"

### 6. Set pubkey in .env
echo "[6/8] Setting pubkey in .env..."
cp -f .env_example .env
sed -i "s|^MINING_PUBKEY=.*|MINING_PUBKEY=$PUBKEY|" "$ENV_FILE"
grep "MINING_PUBKEY" "$ENV_FILE"

### 7. Patch Makefile with pubkey
echo "[7/8] Updating Makefile pubkey..."
if grep -q "^export MINING_PUBKEY" "$MAKEFILE"; then
  sed -i "s|^export MINING_PUBKEY.*|export MINING_PUBKEY := $PUBKEY|" "$MAKEFILE"
else
  echo "export MINING_PUBKEY := $PUBKEY" >> "$MAKEFILE"
fi
grep "MINING_PUBKEY" "$MAKEFILE"

### 8. Launch Miner
echo "[8/8] Launching miner in tmux..."
rm -rf "$PROJECT_DIR/.data.nockchain"
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
tmux new-session -d -s "$TMUX_SESSION" "cd $PROJECT_DIR && $BIN_DIR/nockchain --mining-pubkey $PUBKEY --mine | tee -a miner.log"

echo ""
echo "✅ Nockchain MainNet Miner launched successfully!"
echo "   ➤ To view logs: tmux attach -t $TMUX_SESSION"
echo "   ➤ Wallet pubkey: $PUBKEY"
echo ""
