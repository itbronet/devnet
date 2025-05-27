#!/bin/bash

set -e

echo "== Nockchain Troubleshooting and Setup Script =="

# Determine current directory name
current_dir=$(basename "$PWD")

if [ "$current_dir" = "nockchain" ]; then
    echo "[INFO] You are already inside the nockchain directory."
else
    if [ -d "./nockchain" ]; then
        echo "[INFO] Entering ./nockchain directory..."
        cd ./nockchain || { echo "[ERROR] Could not enter ./nockchain"; exit 1; }
    else
        echo "[WARN] ./nockchain directory not found in current path."
        read -rp "[?] Please enter the full path to your nockchain directory: " nock_path
        cd "$nock_path" || { echo "[ERROR] Could not access $nock_path"; exit 1; }
    fi
fi

# Step 1: Copy .env if missing
if [ ! -f ".env" ]; then
    if [ -f ".env_example" ]; then
        echo "[INFO] .env file not found, copying from .env_example"
        cp .env_example .env
    else
        echo "[ERROR] .env_example file not found! Skipping .env setup."
    fi
fi

# Step 2: Check for missing .jam files
if ! ls ./assets/*.jam >/dev/null 2>&1; then
    echo "[WARN] Missing .jam file in assets directory."
    echo "Please ensure all required .jam asset files are placed under ./nockchain/assets/"
fi

# Step 3: Run cargo fix safely
echo "[INFO] Running cargo fix for nockchain..."
cargo fix --lib -p nockchain --allow-dirty || echo "[WARN] cargo fix encountered issues."

# Step 4: Kill old miner session
echo "[INFO] Cleaning up old processes and ports..."
tmux kill-session -t nock-miner 2>/dev/null || echo "[INFO] No previous tmux session to kill."

# Step 5: Start new miner session
echo "[INFO] Starting tmux session 'nock-miner' for nockchain miner..."
tmux new-session -d -s nock-miner './nockchain.sh'

# Step 6: Test UDP peer connectivity
echo "[INFO] Testing UDP connection to known peers..."
declare -a peers=(
  "183.252.179.3:16536"
  "60.29.93.218:15298"
  "120.226.158.36:36863"
)

for peer in "${peers[@]}"; do
  ip="${peer%%:*}"
  port="${peer##*:}"
  echo "[INFO] Testing UDP to $ip:$port"
  timeout 2 nc -u -v "$ip" "$port" < /dev/null || echo "[WARN] Connection to $ip:$port failed."
done

echo "[INFO] Troubleshooting script completed. Please check warnings above and logs."
