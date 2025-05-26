#!/bin/bash

set -euo pipe

# --- Configuration ---
REPO_URL="https://github.com/zorp-corp/nockchain"
PROJECT_DIR="$HOME/nockchain"
TMUX_SESSION="nockminer"
PUBKEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"
LOG_FILE="$PROJECT_DIR/miner.log"

# --- Cleanup ---
echo ""
echo "[!] Cleaning working directory (except script itself)..."
find . -maxdepth 1 ! -name "$(basename "$0")" ! -name '.' -exec rm -rf {} +
sleep 2
echo "[✔] Directory cleaned."
echo ""

# --- 1. Rust Toolchain ---
echo "[1/9] Installing Rust toolchain..."
if ! command -v cargo &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
fi

# --- 2. System Dependencies ---
echo "[2/9] Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
  git \
  make \
  build-essential \
  clang \
  llvm-dev \
  libclang-dev \
  tmux \
  jq \
  mailutils

# --- 3. Clone or update repository ---
echo "[3/9] Setting up Nockchain repo..."
if [ ! -d "$PROJECT_DIR" ]; then
    echo "Cloning Nockchain repo..."
    git clone "$REPO_URL" "$PROJECT_DIR"
else
    echo "Updating existing repo..."
    cd "$PROJECT_DIR"
    git pull origin main
fi

# --- 4. Ensure assets exist ---
echo "[4/9] Verifying assets..."
ASSETS=("wal.jam" "miner.jam" "dumb.jam")
for file in "${ASSETS[@]}"; do
    if [ ! -f "$PROJECT_DIR/assets/$file" ]; then
        echo "Error: Missing required asset: $file"
        exit 1
    fi
done

# --- 5. Build the project ---
echo "[5/9] Building project..."
cd "$PROJECT_DIR"
cargo build --release

# --- 6. Check binary existence ---
echo "[6/9] Verifying build output..."
if [ ! -f "$PROJECT_DIR/target/release/nockchain" ]; then
    echo "Error: nockchain binary not found after build."
    exit 1
fi

if [ ! -f "$PROJECT_DIR/target/release/nockcli" ]; then
    echo "Error: nockcli binary not found after build."
    exit 1
fi

# --- 7. Kill existing tmux session ---
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

# --- 8. Start miner in tmux ---
echo "[7/9] Starting miner in tmux session '$TMUX_SESSION'..."
tmux new-session -d -s "$TMUX_SESSION" "cd $PROJECT_DIR && ./target/release/nockchain --mine --mining-pubkey $PUBKEY | tee -a $LOG_FILE"

sleep 5

# --- 9. Check wallet balance ---
echo "[8/9] Checking wallet balance..."
BALANCE=$($PROJECT_DIR/target/release/nockcli wallet balance 2>/dev/null)
echo "Wallet Balance: $BALANCE"
echo "$(date): Wallet Balance: $BALANCE" >> "$LOG_FILE"

# --- 10. Optional: Send email alert ---
echo "[9/9] Sending email notification (if mail is installed)..."
if command -v mail &> /dev/null; then
    echo -e "Nockchain Wallet Balance:\n$BALANCE" | mail -s "Nockchain Balance Update" itbronet@gmail.com
fi

# --- Done ---
echo ""
echo "🎉 Setup complete!"
echo "👉 To monitor miner output: tmux attach -t $TMUX_SESSION"
echo "👉 Public Key used: $PUBKEY"
