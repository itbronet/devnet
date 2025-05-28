#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# === Configuration ===
ROOT_DIR="/root/nockchain"
ASSETS_DIR="$ROOT_DIR/assets"
LOG_FILE="$ROOT_DIR/miner.log"
TMUX_SOCKET_DIR="/root/.tmux"
TMUX_SOCKET="$TMUX_SOCKET_DIR/nockminer.sock"
EMAIL="itbronet@gmail.com"
PUBKEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"
TMUX_SESSION="nockminer"

JAM_FILES=( wal.jam miner.jam dumb.jam )
ENV_FILE="$ROOT_DIR/.env"
MAKEFILE="$ROOT_DIR/Makefile"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
err() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

prepare_tmux_socket_dir() {
  if [ ! -d "$TMUX_SOCKET_DIR" ]; then
    mkdir -p "$TMUX_SOCKET_DIR"
    chmod 700 "$TMUX_SOCKET_DIR"
    log "Created tmux socket directory $TMUX_SOCKET_DIR"
  fi
}

install_postfix_noninteractive() {
  if ! dpkg -s postfix &>/dev/null; then
    log "Installing postfix mail server non-interactively..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    echo "postfix postfix/main_mailer_type string Internet Site" | debconf-set-selections
    apt-get install -y postfix mailutils || {
      err "Failed to install postfix/mailutils"
      exit 1
    }
    systemctl restart postfix || true
    log "Postfix installed and restarted"
  else
    log "Postfix already installed"
  fi
}

check_and_install_prereqs() {
  log "Checking prerequisite packages..."
  local pkgs=(build-essential curl git tmux mailutils pkg-config libssl-dev)

  for pkg in "${pkgs[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
      log "Installing missing package: $pkg"
      apt-get install -y "$pkg"
    else
      log "Package $pkg already installed"
    fi
  done

  if ! command -v rustc &>/dev/null; then
    log "Rust not found, installing rustup & Rust..."
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    source "$HOME/.cargo/env"
  else
    log "Rust already installed"
  fi

  rustc --version
}

clone_or_update_repo() {
  if [ ! -d "$ROOT_DIR" ]; then
    log "Cloning nockchain repository..."
    git clone https://github.com/zorp-corp/nockchain.git "$ROOT_DIR"
  else
    log "Updating existing nockchain repository..."
    cd "$ROOT_DIR"
    git fetch --all
    git reset --hard origin/master
  fi
}

verify_assets() {
  log "Verifying assets directory and jam files..."

  mkdir -p "$ASSETS_DIR"
  local missing=0
  for jam in "${JAM_FILES[@]}"; do
    if [ ! -f "$ASSETS_DIR/$jam" ]; then
      err "Missing asset file: $jam in $ASSETS_DIR"
      missing=1
    else
      log "Found asset: $jam"
    fi
  done

  if [ "$missing" -eq 1 ]; then
    err "One or more asset files are missing. Please place wal.jam, miner.jam, dumb.jam inside $ASSETS_DIR"
    exit 1
  fi
}

write_env_file() {
  log "Writing .env file with mining pubkey..."
  cp -f "$ROOT_DIR/.env_example" "$ENV_FILE"
  sed -i "s|^MINING_PUBKEY=.*|MINING_PUBKEY=$PUBKEY|" "$ENV_FILE"
  log "MINING_PUBKEY=$PUBKEY"
}

patch_makefile() {
  log "Patching Makefile with mining pubkey..."
  if grep -q "^export MINING_PUBKEY" "$MAKEFILE"; then
    sed -i "s|^export MINING_PUBKEY.*|export MINING_PUBKEY := $PUBKEY|" "$MAKEFILE"
  else
    echo "export MINING_PUBKEY := $PUBKEY" >> "$MAKEFILE"
  fi
}

build_project() {
  log "Building Nockchain with make..."
  cd "$ROOT_DIR"
  make install-hoonc
  make build
  make install-nockchain
  make install-nockchain-wallet
  make install-nockchain-miner
  make install-nockchain-verifier
  log "Build completed successfully"
}

kill_miner_sessions() {
  log "Killing existing miner processes and tmux sessions..."
  pkill -f nockchain || true
  tmux -S "$TMUX_SOCKET" kill-session -t "$TMUX_SESSION" 2>/dev/null || true
}

launch_miner_tmux() {
  kill_miner_sessions
  log "Launching miner in tmux session with mining pubkey..."
  cd "$ROOT_DIR"
  : > "$LOG_FILE"
  tmux -S "$TMUX_SOCKET" new-session -d -s "$TMUX_SESSION" \
    "./target/release/nockchain --mine --mining-pubkey $PUBKEY | tee -a $LOG_FILE"
  log "Miner launched, waiting 30 seconds for startup..."
  sleep 30
}

test_mining_activity() {
  log "Testing mining activity in miner.log..."

  if ! pgrep -f nockchain >/dev/null; then
    err "Miner process is NOT running"
    echo "Nockchain miner process not running after launch" | mail -s "Nockchain Miner Error" "$EMAIL"
    exit 1
  fi

  if grep -q "block by-height" "$LOG_FILE"; then
    log "Mining activity detected!"
    echo "Nockchain mining started successfully" | mail -s "Nockchain Miner Started" "$EMAIL"
  else
    err "No mining activity detected in logs"
    echo "Nockchain mining failed to start or no blocks found" | mail -s "Nockchain Miner Error" "$EMAIL"
    exit 1
  fi
}

# === Main ===

log "=== Starting Nockchain setup and miner launch ==="

prepare_tmux_socket_dir
install_postfix_noninteractive
check_and_install_prereqs
clone_or_update_repo
verify_assets
write_env_file
patch_makefile
build_project
launch_miner_tmux
test_mining_activity

log "=== Setup and launch complete ==="
