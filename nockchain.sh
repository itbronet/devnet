#!/bin/bash

set -euo pipefail

# --- Configuration ---
REPO_URL="https://github.com/zorp-corp/nockchain"
PROJECT_DIR="$HOME/nockchain"
ASSETS_DIR="$PROJECT_DIR/assets"
TMUX_SESSION="nockminer"
BINARY_NAME="nockchaind"
BINARY_PATH="$HOME/.local/bin/$BINARY_NAME"
PUBKEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"
LOG_FILE="$PROJECT_DIR/miner.log"

# --- Check if inside a git repository ---
if [ ! -d .git ]; then
  echo "❌ Error: You must run this script inside a cloned Git repository."
  exit 1
fi

# --- Detect correct branch ---
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")

# --- Ensure Rust toolchain ---
echo "[1/9] Installing Rust toolchain..."
if ! command -v cargo &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
fi

# --- Install System Dependencies ---
echo "[2/9] Installing system dependencies..."
sudo apt-get update && sudo apt-get install -y \
  git make build-essential clang llvm-dev libclang-dev tmux

# --- Clone or update repository ---
echo "[3/9] Cloning or updating Nockchain repo..."
if [ ! -d "$PROJECT_DIR" ]; then
  git clone "$REPO_URL" "$PROJECT_DIR"
else
  cd "$PROJECT_DIR"
  git pull origin "$BRANCH"
  cd -
fi

# --- Create dummy kernel assets ---
echo "[4/9] Creating dummy .jam kernel files..."
mkdir -p "$ASSETS_DIR"
echo ":: Dummy wallet logic" > "$ASSETS_DIR/wal.jam"
echo ":: Dummy miner logic" > "$ASSETS_DIR/miner.jam"
echo ":: Dummy dumb logic" > "$ASSETS_DIR/dumb.jam"

# --- Git commit asset files ---
echo "[5/9] Committing kernel files to GitHub..."
git add "$ASSETS_DIR"/*.jam
if git diff --cached --quiet; then
  echo "No changes to commit."
else
  git commit -m "Add dummy kernel .jam files"
  git push origin "$BRANCH"
fi

# --- Build the project ---
echo "[6/9] Building project..."
cd "$PROJECT_DIR"
cargo build --release

# --- Verify binaries ---
echo "[7/9] Verifying binaries..."
if [ ! -f "$PROJECT_DIR/target/release/nockchain" ]; then
  echo "Error: nockchain binary not found."
  exit 1
fi
if [ ! -f "$PROJECT_DIR/target/release/nockcli" ]; then
  echo "Error: nockcli binary not found."
  exit 1
fi

# --- Start miner in tmux ---
echo "[8/9] Starting miner in tmux..."
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
tmux new-session -d -s "$TMUX_SESSION" "cd $PROJECT_DIR && ./target/release/nockchain --mine --mining-pubkey $PUBKEY | tee -a $LOG_FILE"

# --- Wallet balance ---
echo "[9/9] Checking wallet balance..."
BALANCE=$("$PROJECT_DIR/target/release/nockcli" wallet balance 2>/dev/null || echo "Unavailable")
echo "Wallet Balance: $BALANCE"
echo "$(date): Wallet Balance: $BALANCE" >> "$LOG_FILE"

# --- Done ---
echo "🎉 Setup complete!"
echo "👉 To monitor miner output: tmux attach -t $TMUX_SESSION"
echo "👉 Public Key used: $PUBKEY"
