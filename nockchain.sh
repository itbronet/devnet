#!/bin/bash

set -euo pipefail

# Configuration
REPO_URL="https://github.com/zorp-corp/nockchain"
PROJECT_DIR="$HOME/nockchain"
ASSET_DIR="$PROJECT_DIR/assets"
TMUX_SESSION="nockminer"
PUBKEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"
LOG_FILE="$PROJECT_DIR/miner.log"

# GitHub Commit Config
GITHUB_REPO="https://github.com/itbronet/devnet"
TARGET_BRANCH="main"
COMMIT_MESSAGE="Auto-added .jam kernel files"
GIT_USER="bronetsystem"
GIT_EMAIL="itbronet@gmail.com"
GH_TOKEN="${GH_TOKEN:-}"

# Ensure Rust
echo "[1/9] Installing Rust if needed..."
if ! command -v cargo &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
fi

# System dependencies
echo "[2/9] Installing packages..."
sudo apt-get update
sudo apt-get install -y git make build-essential clang llvm-dev libclang-dev tmux

# Clone Nockchain repo
echo "[3/9] Cloning or updating Nockchain..."
if [ ! -d "$PROJECT_DIR" ]; then
  git clone "$REPO_URL" "$PROJECT_DIR"
else
  cd "$PROJECT_DIR"
  git pull origin main
fi

mkdir -p "$ASSET_DIR"

# Create .jam files
echo "[4/9] Creating dummy .jam kernel files..."
cat > "$ASSET_DIR/wal.jam" << 'EOF'
[+*  %wallet
  =$
  $coin  @ud
  $owner @pub
]
EOF

cat > "$ASSET_DIR/miner.jam" << 'EOF'
[+*  %miner
  =$
  $difficulty @ud
  $timestamp  @da
]
EOF

cat > "$ASSET_DIR/dumb.jam" << 'EOF'
[+*  %dumb
  =$
  $id @ta
]
EOF

# Verify presence
echo "[5/9] Verifying .jam assets..."
for f in wal.jam miner.jam dumb.jam; do
  if [ ! -f "$ASSET_DIR/$f" ]; then
    echo "❌ Missing $f"
    exit 1
  fi
done

# Commit to your GitHub repo
if [ -n "$GH_TOKEN" ]; then
  echo "[6/9] Committing .jam files to $GITHUB_REPO..."
  TMP_CLONE="$HOME/tmp-jam-push"
  rm -rf "$TMP_CLONE"
  git clone "https://$GH_TOKEN@github.com/itbronet/devnet" "$TMP_CLONE"
  cd "$TMP_CLONE"
  mkdir -p assets
  cp "$ASSET_DIR/"*.jam assets/
  git config user.name "$GIT_USER"
  git config user.email "$GIT_EMAIL"
  git add assets/*.jam
  git commit -m "$COMMIT_MESSAGE" || echo "No changes to commit."
  git push origin "$TARGET_BRANCH"
  cd ~
  rm -rf "$TMP_CLONE"
else
  echo "⚠️  GH_TOKEN not set, skipping GitHub commit."
fi

# Build project
echo "[7/9] Building Nockchain..."
cd "$PROJECT_DIR"
cargo build --release

# Validate build
if [ ! -f "$PROJECT_DIR/target/release/nockchain" ]; then
  echo "❌ nockchain binary missing"
  exit 1
fi

if [ ! -f "$PROJECT_DIR/target/release/nockcli" ]; then
  echo "❌ nockcli binary missing"
  exit 1
fi

# Start miner in tmux
echo "[8/9] Starting miner in tmux..."
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
tmux new-session -d -s "$TMUX_SESSION" "cd $PROJECT_DIR && ./target/release/nockchain --mine --mining-pubkey $PUBKEY | tee -a $LOG_FILE"

sleep 5

# Wallet check
echo "[9/9] Checking wallet balance..."
BALANCE=$($PROJECT_DIR/target/release/nockcli wallet balance 2>/dev/null || echo "Unavailable")
echo "Wallet Balance: $BALANCE"
echo "$(date): Wallet Balance: $BALANCE" >> "$LOG_FILE"

echo "🎉 Mining started in tmux session '$TMUX_SESSION'"
echo "👉 Attach: tmux attach -t $TMUX_SESSION"
echo "👉 Public Key: $PUBKEY"
