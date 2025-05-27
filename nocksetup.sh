#!/bin/bash

# === CONFIGURATION ===
SESSION="nockminer"
LOGFILE="nockminer.log"
REPO_DIR="$HOME/nockchain"
PUBLIC_KEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"  # Replace with your actual public key

# === FUNCTIONS ===

install_rust() {
    if ! command -v rustc &> /dev/null; then
        echo "[INFO] Rust not found, installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    else
        echo "[INFO] Rust already installed."
    fi
}

clone_or_update_repo() {
    if [ ! -d "$REPO_DIR" ]; then
        echo "[INFO] Cloning nockchain repo..."
        git clone https://github.com/zorp-corp/nockchain.git "$REPO_DIR"
    else
        echo "[INFO] Updating existing repo..."
        cd "$REPO_DIR" || exit 1
        git pull origin master
    fi
}

build_nockchain() {
    echo "[INFO] Building nockchain release..."
    cd "$REPO_DIR" || exit 1
    cargo build --release
}

cleanup() {
    echo "[INFO] Cleaning up old processes and ports..."

    pkill -f nockchain 2>/dev/null
    sudo fuser -k 30333/tcp 2>/dev/null
    sudo fuser -k 4001/tcp 2>/dev/null
    sudo fuser -k 9000/tcp  2>/dev/null
    tmux kill-session -t "$SESSION" 2>/dev/null
}

start_miner() {
    echo "[INFO] Starting miner in tmux session: $SESSION"
    cd "$REPO_DIR" || exit 1

    # Export public key environment variable (adjust if your miner uses a different method)
    export NOCKCHAIN_PUBLIC_KEY="$PUBLIC_KEY"

    tmux new-session -d -s "$SESSION" "cargo run --bin nockchain --release > $LOGFILE 2>&1"

    sleep 5

    if tmux has-session -t "$SESSION" 2>/dev/null; then
        echo "[INFO] ✅ Miner running in tmux session '$SESSION'."
        echo "[INFO] View logs: tail -f $LOGFILE"
        echo "[INFO] Attach: tmux attach -t $SESSION"
    else
        echo "[ERROR] ❌ Miner failed to start. Check $LOGFILE."
        exit 1
    fi
}

# === MAIN SCRIPT ===

install_rust
clone_or_update_repo
build_nockchain
cleanup
start_miner
