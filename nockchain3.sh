#!/bin/bash

set -euo pipefail

# Constants
ROOT_DIR="/root/nockchain"
ASSET_DIR="$ROOT_DIR/assets"
LOG_FILE="$ROOT_DIR/miner.log"
EMAIL="itbronet@gmail.com"
GIT_REPO="https://github.com/zorp-corp/nockchain.git"
MINER_SESSION="nockminer"

log() {
  echo "[✔] $1"
}

err() {
  echo "[✘] $1" >&2
  echo "$1" | mail -s "Nockchain Setup Failed" "$EMAIL" || true
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

install_prereqs() {
  log "Installing prerequisites..."
  apt-get update -y
  apt-get install -y build-essential curl git tmux mailutils postfix pkg-config libssl-dev || err "Failed to install dependencies"
  if ! command_exists rustup; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  fi
  export PATH="$HOME/.cargo/bin:$PATH"
}

clone_repo() {
  log "Cloning or updating nockchain repo..."
  mkdir -p "$ROOT_DIR"
  cd "$ROOT_DIR"
  if [ -d ".git" ]; then
    git pull || err "Failed to update repository"
  else
    git clone "$GIT_REPO" . || err "Git clone failed"
  fi
}

create_assets() {
  log "Creating assets directory and .jam files..."
  mkdir -p "$ASSET_DIR"
  for file in wal.jam miner.jam dumb.jam; do
    # If file does not exist or is empty, create a placeholder
    if [ ! -s "$ASSET_DIR/$file" ]; then
      echo "// placeholder $file" > "$ASSET_DIR/$file"
      log "Created placeholder $file"
    else
      log "$file exists"
    fi
  done
}

build_nockchain() {
  log "Building nockchain (release)..."
  export PATH="$HOME/.cargo/bin:$PATH"
  cd "$ROOT_DIR"
  cargo clean
  cargo build --release || err "Build failed"
}

launch_miner_tmux() {
  log "Killing existing miner sessions and launching a new one..."
  pkill -f nockchain || true
  tmux kill-session -t "$MINER_SESSION" || true
  cd "$ROOT_DIR"
  # Clear old log before starting
  : > "$LOG_FILE"
  tmux new-session -d -s "$MINER_SESSION" "cargo run --bin nockchain --release > $LOG_FILE 2>&1"
  sleep 10
}

test_mining_log() {
  log "Testing mining activity in log..."
  # Give some time for miner to produce output
  sleep 20
  if grep -q "block by-height" "$LOG_FILE"; then
    log "Mining is working properly!"
    echo "Nockchain mining started successfully" | mail -s "Nockchain Mining Started" "$EMAIL"
  else
    err "No mining activity detected in log after startup."
  fi
}

setup_cron_reboot() {
  log "Setting up cron job to auto-start miner on reboot..."
  # Append only if not already present
  (crontab -l 2>/dev/null | grep -v "$ROOT_DIR/nockchain.sh" || true; echo "@reboot bash $ROOT_DIR/nockchain.sh") | sort -u | crontab -
}

main() {
  log "Starting Nockchain setup..."
  install_prereqs
  clone_repo
  create_assets
  build_nockchain
  launch_miner_tmux
  test_mining_log
  setup_cron_reboot
  log "Nockchain setup completed successfully."
}

main
