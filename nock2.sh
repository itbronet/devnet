#!/bin/bash

################################################################################
# run_nockchain_miner.sh
# Author: You!
# Description: Sets up and runs the Nockchain miner node with your public key.
################################################################################

# Navigate to the script directory's parent (project root)
cd "$(dirname "$0")/.." || {
  echo "❌ Failed to change directory to project root"
  exit 1
}

echo "🚀 Starting Nockchain Miner Setup..."

#############################################
# 1. Check for Rust installation
#############################################
if ! command -v cargo &> /dev/null; then
    echo "⚠️  Rust is not installed. Installing Rust now..."
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    source "$HOME/.cargo/env"
else
    echo "✅ Rust is already installed."
fi

#############################################
# 2. Set environment variables
#############################################
export MINING_PUBKEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"
export RUST_LOG="info,nockchain=info,nockchain_libp2p_io=info,libp2p=info,libp2p_quic=info"
export RUST_BACKTRACE=full
export MINIMAL_LOG_FORMAT=true

echo "🔑 Using Mining Public Key:"
echo "$MINING_PUBKEY"

#############################################
# 3. Build Rust components
#############################################
echo "🔧 Building Rust components..."
make build-rust || {
    echo "❌ Rust build failed. Exiting."
    exit 1
}

#############################################
# 4. Build Hoon components
#############################################
echo "📜 Building Hoon components..."
make build-hoon-all || {
    echo "❌ Hoon build failed. Exiting."
    exit 1
}

#############################################
# 5. Run the Nockchain miner
#############################################
echo "⛏️  Starting Nockchain Miner Node..."
make run-nockchain

echo "✅ Nockchain miner is now running."
