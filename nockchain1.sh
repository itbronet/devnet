#!/bin/bash

set -euo pipefail

### CONFIGURATION ###
REPO_URL="https://github.com/zorp-corp/nockchain.git"
CLONE_DIR="$HOME/nockchain"
SOCKET_PATH="$CLONE_DIR/.socket/nockchain.sock"
LOG_FILE="$CLONE_DIR/nockminer.log"
TMUX_SESSION="nockminer"
EMAIL_TO="itbronet@gmail.com"
PUBKEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"

EMAIL_SUBJECT_PREFIX="[Nockchain Setup]"

### Ensure dependencies ###
echo "[*] Installing dependencies..."
apt-get update -y
apt-get install -y build-essential curl git tmux mailutils

### Ensure Rust ###
if ! command -v rustc >/dev/null 2>&1; then
    echo "[*] Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

export PATH="$HOME/.cargo/bin:$PATH"

### Clone or update repo ###
if [ -d "$CLONE_DIR/.git" ]; then
    echo "[*] Updating Nockchain repo..."
    git -C "$CLONE_DIR" reset --hard
    git -C "$CLONE_DIR" pull
else
    echo "[*] Cloning Nockchain repo..."
    git clone "$REPO_URL" "$CLONE_DIR"
fi

cd "$CLONE_DIR"

### Clean stale socket if needed ###
[ -S "$SOCKET_PATH" ] && echo "[*] Removing stale socket..." && rm -f "$SOCKET_PATH"

### Build step with recovery ###
echo "[*] Building Nockchain..."
if ! cargo build --release; then
    echo "[!] Initial build failed, retrying with clean..."
    cargo clean
    if ! cargo build --release; then
        echo "[!] Build failed again. Sending alert."
        echo "Nockchain build failed even after retrying with cargo clean." | mail -s "$EMAIL_SUBJECT_PREFIX Build Failure" "$EMAIL_TO"
        exit 1
    fi
fi

### Kill any old tmux session ###
tmux has-session -t "$TMUX_SESSION" 2>/dev/null && tmux kill-session -t "$TMUX_SESSION"

### Launch miner in tmux ###
echo "[*] Launching miner in tmux..."
tmux new-session -d -s "$TMUX_SESSION" "cargo run --bin nockchain --release > $LOG_FILE 2>&1"

sleep 5

### Check for miner socket ###
if [ ! -S "$SOCKET_PATH" ]; then
    echo "[!] Miner failed to start, retrying..."
    tmux kill-session -t "$TMUX_SESSION"
    sleep 2
    tmux new-session -d -s "$TMUX_SESSION" "cargo run --bin nockchain --release > $LOG_FILE 2>&1"
    sleep 5

    if [ ! -S "$SOCKET_PATH" ]; then
        echo "Miner failed to launch after retry. Check logs." | mail -s "$EMAIL_SUBJECT_PREFIX Miner Startup Failure" "$EMAIL_TO"
        exit 1
    fi
fi

### Monitor logs for alerts (background) ###
echo "[*] Setting up log watcher..."
(pkill -f "tail -F $LOG_FILE" || true) 2>/dev/null
(tail -F "$LOG_FILE" | while read -r line; do
    if echo "$line" | grep -q "block by-height"; then
        echo -e "🎉 Block mined:\n\n$line" | mail -s "$EMAIL_SUBJECT_PREFIX Block Mined" "$EMAIL_TO"
    elif echo "$line" | grep -i -q "panic"; then
        echo -e "🚨 Panic detected:\n\n$line" | mail -s "$EMAIL_SUBJECT_PREFIX Panic Detected" "$EMAIL_TO"
    fi
done) &

### Validate miner tmux is alive ###
if ! tmux capture-pane -t "$TMUX_SESSION" \; list-panes | grep -q "nockchain"; then
    echo "[!] Tmux miner pane is dead. Relaunching..."
    tmux kill-session -t "$TMUX_SESSION"
    tmux new-session -d -s "$TMUX_SESSION" "cargo run --bin nockchain --release > $LOG_FILE 2>&1"
    sleep 5
    if ! tmux capture-pane -t "$TMUX_SESSION" \; list-panes | grep -q "nockchain"; then
        echo "Miner crashed repeatedly. Check manually." | mail -s "$EMAIL_SUBJECT_PREFIX Miner Crash Loop" "$EMAIL_TO"
        exit 1
    fi
fi

### Check wallet balance ###
echo "[*] Checking wallet balance..."
"$CLONE_DIR/target/release/nockchain-wallet" \
  --nockchain-socket "$SOCKET_PATH" \
  list-notes-by-pubkey -p "$PUBKEY" || {
    echo "[!] Wallet command failed. Possibly miner not ready." | mail -s "$EMAIL_SUBJECT_PREFIX Wallet Failed" "$EMAIL_TO"
}

echo "[✓] Nockchain setup complete and mining started."
