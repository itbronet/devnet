#!/bin/bash
# Final nockchain.sh setup script
# Author: BRONET LTD
# Description: Fully automated setup, build, asset creation, miner launch, log alerts, and reboot resilience.

set -euo pipefail

# ========= CONFIGURATION ========= #
REPO_URL="https://github.com/zorp-corp/nockchain.git"
INSTALL_DIR="$HOME/nockchain"
ASSETS_DIR="$INSTALL_DIR/assets"
EMAIL="itbronet@gmail.com"
PUBLIC_KEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"

# ========= PREREQUISITES ========= #
echo "[+] Installing prerequisites..."
apt-get update -y && apt-get install -y git curl tmux postfix mailutils build-essential pkg-config libssl-dev

# Avoid postfix freeze
export DEBIAN_FRONTEND=noninteractive

# ========= INSTALL RUST ========= #
echo "[+] Installing Rust..."
if ! command -v cargo >/dev/null 2>&1; then
  curl https://sh.rustup.rs -sSf | sh -s -- -y
  source "$HOME/.cargo/env"
fi

# ========= CLONE OR UPDATE REPO ========= #
echo "[+] Cloning or updating repository..."
if [ ! -d "$INSTALL_DIR" ]; then
  git clone "$REPO_URL" "$INSTALL_DIR"
else
  cd "$INSTALL_DIR"
  git pull
fi

# ========= CREATE ASSETS ========= #
echo "[+] Creating assets..."
mkdir -p "$ASSETS_DIR"
echo "// wallet kernel" > "$ASSETS_DIR/wal.jam"
echo "// miner kernel" > "$ASSETS_DIR/miner.jam"
echo "// dumb kernel" > "$ASSETS_DIR/dumb.jam"

# ========= BUILD ========= #
echo "[+] Building project..."
cd "$INSTALL_DIR"
cargo build --release || { echo "[-] Build failed"; exit 1; }

# ========= TESTING ========= #
echo "[+] Verifying build and assets..."
for FILE in wal.jam miner.jam dumb.jam; do
  if [ ! -f "$ASSETS_DIR/$FILE" ]; then
    echo "[-] Missing asset: $FILE"
    exit 1
  fi
done

if [ ! -f "target/release/nockchain" ]; then
  echo "[-] Build output missing"
  exit 1
fi

# ========= LOG-BASED ALERTS ========= #
echo "[+] Setting up alert system..."
tmux kill-session -t logwatcher 2>/dev/null || true
tmux new-session -d -s logwatcher "tail -Fn0 $INSTALL_DIR/miner.log | grep --line-buffered 'block by-height' | while read line; do echo \"[BLOCK FOUND] \$line\" | mail -s 'Nockchain Block Mined' $EMAIL; done"

# ========= START MINER ========= #
echo "[+] Starting miner in tmux..."
tmux kill-session -t nockminer 2>/dev/null || true
tmux new-session -d -s nockminer "$INSTALL_DIR/target/release/nockchain > $INSTALL_DIR/miner.log 2>&1"

# ========= CRON REBOOT SETUP ========= #
echo "[+] Adding cron job for auto-restart on reboot..."
(crontab -l 2>/dev/null; echo "@reboot bash $HOME/nockchain.sh") | sort -u | crontab -

# ========= DONE ========= #
echo "[✓] Nockchain setup complete. Mining has started."
tmux ls
