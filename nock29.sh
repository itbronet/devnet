#!/bin/bash

# --- Configuration ---
REPO_URL="https://github.com/zorp-corp/nockchain"
PROJECT_DIR="$HOME/nockchain"
TMUX_SESSION="nockminer"
PUBKEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"
LOG_FILE="$HOME/nockchain/miner.log"

# --- Update system and install dependencies ---
sudo apt update && sudo apt install -y build-essential curl git tmux mailutils jq

# --- Install Rust if not present ---
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# --- Clone or update repository ---
if [ ! -d "$PROJECT_DIR" ]; then
    echo "Cloning Nockchain repo..."
    git clone "$REPO_URL" "$PROJECT_DIR"
else
    echo "Updating existing repo..."
    cd "$PROJECT_DIR"
    git pull origin main
fi

cd "$PROJECT_DIR"

# --- Build the project ---
echo "Building project..."
cargo build --release

# --- Check binary existence ---
if [ ! -f "$PROJECT_DIR/target/release/nockchain" ]; then
    echo "Error: nockchain binary not found after build."
    exit 1
fi

if [ ! -f "$PROJECT_DIR/target/release/nockcli" ]; then
    echo "Error: nockcli binary not found after build."
    exit 1
fi

# --- Kill existing tmux session ---
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

# --- Start miner in tmux ---
echo "Starting miner in tmux session '$TMUX_SESSION'..."
tmux new-session -d -s "$TMUX_SESSION" "cd $PROJECT_DIR && ./target/release/nockchain --mine --mining-pubkey $PUBKEY | tee -a $LOG_FILE"

sleep 5

# --- Check wallet balance ---
BALANCE=$($PROJECT_DIR/target/release/nockcli wallet balance 2>/dev/null)
echo "Wallet Balance: $BALANCE"
echo "$(date): Wallet Balance: $BALANCE" >> "$LOG_FILE"

# --- Optional: Send email alert ---
if command -v mail &> /dev/null; then
    echo -e "Nockchain Wallet Balance:\n$BALANCE" | mail -s "Nockchain Balance Update" itbronet@gmail.com
fi

echo "🎉 Setup complete!"
echo "👉 To monitor miner output: tmux attach -t $TMUX_SESSION"
echo "👉 Public Key used: $PUBKEY"
