#!/bin/bash

set -e
set -u
set -o pipefail

# --- Configuration ---
REPO_URL="https://github.com/zorp-corp/nockchain"
PROJECT_DIR="$HOME/nockchain"
ASSETS_DIR="$PROJECT_DIR/assets"
TMUX_SESSION="nockminer"
PUBKEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"
LOG_FILE="$PROJECT_DIR/miner.log"

echo ""
echo "[!] Cleaning old build..."
rm -rf "$PROJECT_DIR"
sleep 2
echo "[✔] Old project cleaned."

# --- Install Rust toolchain if not present ---
echo "[1/8] Checking Rust installation..."
if ! command -v cargo &>/dev/null; then
  echo "Rust not found. Installing Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
else
  echo "Rust already installed."
fi

# --- Install system dependencies ---
echo "[2/8] Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
  git \
  make \
  build-essential \
  clang \
  llvm-dev \
  libclang-dev \
  tmux \
  jq

# --- Clone the repository ---
echo "[3/8] Cloning Nockchain repository..."
git clone "$REPO_URL" "$PROJECT_DIR"

# --- Verify required assets exist ---
echo "[4/8] Verifying assets..."
REQUIRED_ASSETS=("wal.jam" "miner.jam" "dumb.jam")
for asset in "${REQUIRED_ASSETS[@]}"; do
  if [ ! -f "$ASSETS_DIR/$asset" ]; then
    echo "Error: Missing required asset: $asset"
    exit 1
  fi
done

# --- Build the project ---
echo "[5/8] Building the project..."
cd "$PROJECT_DIR"
cargo build --release

# --- Check if binaries were built ---
echo "[6/8] Verifying binaries..."
if [ ! -f "$PROJECT_DIR/target/release/nockchain" ]; then
    echo "Error: nockchain binary not found."
    exit 1
fi

if [ ! -f "$PROJECT_DIR/target/release/nockcli" ]; then
    echo "Error: nockcli binary not found."
    exit 1
fi

# --- Kill existing tmux session if running ---
echo "[7/8] Killing previous tmux session (if exists)..."
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

# --- Start miner ---
echo "[8/8] Starting miner in tmux session '$TMUX_SESSION'..."
tmux new-session -d -s "$TMUX_SESSION" "cd $PROJECT_DIR && ./target/release/nockchain --mine --mining-pubkey $PUBKEY | tee -a $LOG_FILE"
sleep 5

# --- Show wallet balance ---
BALANCE=$($PROJECT_DIR/target/release/nockcli wallet balance 2>/dev/null || echo "Unable to fetch balance")
echo "Wallet Balance: $BALANCE"
echo "$(date): Wallet Balance: $BALANCE" >> "$LOG_FILE"

# --- Optional: Email alert ---
if command -v mail &>/dev/null; then
  echo -e "Nockchain Wallet Balance:\n$BALANCE" | mail -s "Nockchain Miner Started - Balance Update" itbronet@gmail.com
fi

echo ""
echo "✅ Setup complete!"
echo "📍 To view logs: tmux attach -t $TMUX_SESSION"
echo "🔑 Mining with public key: $PUBKEY"
