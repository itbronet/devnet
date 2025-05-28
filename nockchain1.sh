#!/bin/bash

set -euo pipefail

### CONFIGURATION ###
REPO_URL="https://github.com/zorp-corp/nockchain.git"
REPO_DIR="$HOME/nockchain"
ASSETS_DIR="$REPO_DIR/assets"
PUBLIC_KEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"
EMAIL="itbronet@gmail.com"
TMUX_SESSION="nockminer"
LOG_FILE="$REPO_DIR/nockminer.log"
DEBIAN_FRONTEND=noninteractive

### UTILITIES ###
log() { echo -e "\033[1;32m[✔]\033[0m $1"; }
err() { echo -e "\033[1;31m[✘]\033[0m $1" >&2; }

### 1. Prerequisites ###
log "Installing prerequisites..."
apt-get update -y
apt-get install -y curl git tmux postfix mailutils ufw build-essential pkg-config libssl-dev \
    || (echo "Postfix failed interactively, retrying in noninteractive mode..." && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y postfix)

if ! command -v rustc &> /dev/null; then
  log "Installing Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
fi

### 2. Clone or Pull Repo ###
if [ ! -d "$REPO_DIR/.git" ]; then
  log "Cloning Nockchain repo..."
  git clone "$REPO_URL" "$REPO_DIR"
else
  log "Pulling latest changes..."
  cd "$REPO_DIR"
  git reset --hard
  git pull origin master
fi

### 3. Setup Assets ###
log "Ensuring assets exist..."
mkdir -p "$ASSETS_DIR"

create_dummy_jam() {
  local f="$1"
  if [ ! -f "$ASSETS_DIR/$f" ]; then
    echo "-- dummy $f for nockchain bootstrapping" > "$ASSETS_DIR/$f"
  fi
}
create_dummy_jam "wal.jam"
create_dummy_jam "miner.jam"
create_dummy_jam "dumb.jam"

### 4. Build ###
log "Building nockchain..."
cd "$REPO_DIR"
cargo clean
cargo build --release || (err "Build failed!" && exit 1)

### 5. Wallet Setup ###
if [ ! -f "$REPO_DIR/wallet.txt" ]; then
  log "Creating wallet..."
  ./target/release/nockchain key new > wallet.txt
fi

### 6. Miner Startup via tmux ###
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  log "Killing existing tmux session..."
  tmux kill-session -t "$TMUX_SESSION"
fi

log "Starting miner in tmux..."
tmux new-session -d -s "$TMUX_SESSION" "cd $REPO_DIR && cargo run --bin nockchain --release > $LOG_FILE 2>&1"

### 7. Email Alert Setup ###
log "Setting up log watcher for mined blocks..."
pkill -f "tail -f $LOG_FILE" || true
nohup bash -c "tail -F $LOG_FILE | grep --line-buffered 'block by-height' | while read -r line; do echo \"\$line\" | mail -s 'Nockchain Block Mined' $EMAIL; done" >/dev/null 2>&1 &

log "Setup complete! Miner running in tmux. Wallet stored in wallet.txt."
