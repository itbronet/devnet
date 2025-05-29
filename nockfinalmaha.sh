#!/bin/bash
set -e

# === Step 1: Install Dependencies ===
echo "Updating packages and installing dependencies..."
sudo apt-get update && sudo apt-get upgrade -y

sudo apt install -y curl iptables build-essential git wget lz4 jq make gcc nano \
automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev \
libleveldb-dev tar clang bsdmainutils ncdu unzip libclang-dev llvm-dev screen

# Install Rust
if ! command -v rustc &> /dev/null; then
  echo "Installing Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
source $HOME/.cargo/env

# Enable memory overcommit
sudo sysctl -w vm.overcommit_memory=1

# === Step 2: Delete old repo and wipe all data ===
echo "Stopping old miner screen sessions and removing old data..."
screen -ls | grep miner && screen -XS miner quit || echo "No miner screen to quit."
rm -rf nockchain
rm -rf .nockapp

# === Step 3: Clone Nockchain repo ===
echo "Cloning Nockchain repository..."
git clone https://github.com/zorp-corp/nockchain
cd nockchain

# === Step 4: Build ===
echo "Copying example .env and building project..."
cp .env_example .env

make install-hoonc

export PATH="$HOME/.cargo/bin:$PATH"
make build
make install-nockchain-wallet

export PATH="$HOME/.cargo/bin:$PATH"
make install-nockchain

export PATH="$HOME/.cargo/bin:$PATH"

# === Step 5: Setup wallet ===
echo "Generating wallet keys..."
nockchain-wallet keygen

echo "IMPORTANT: Replace MINING_PUBKEY in .env with your public key:"
echo "Your Public Key:"
echo "35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"
echo "Use 'nano .env' to edit it now."
read -p "Press Enter after editing the .env file to continue..."

# === Step 6: Backup wallet keys ===
echo "Exporting wallet keys to keys.export..."
nockchain-wallet export-keys
echo "Make sure keys.export is saved securely."

# === Step 7: Run Miner ===
echo "Enabling memory overcommit (again)..."
sudo sysctl -w vm.overcommit_memory=1

echo "Setting up miner instance in screen..."

mkdir -p ~/nockchain/miner1
cd ~/nockchain/miner1

screen -dmS miner1 bash -c "
  export PATH=\"$HOME/.cargo/bin:\$PATH\"
  RUST_LOG=info,nockchain=info,nockchain_libp2p_io=info,libp2p=info,libp2p_quic=info \
  MINIMAL_LOG_FORMAT=true \
  nockchain --mine --mining-pubkey 35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R
"

echo "Miner instance 'miner1' started inside a detached screen session."
echo "Use 'screen -r miner1' to attach to the miner screen."
echo "Use 'htop' to monitor RAM usage."
