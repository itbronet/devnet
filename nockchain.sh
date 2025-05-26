#!/bin/bash

set -euo pipefail

# --- Configuration ---
REPO_URL="https://github.com/zorp-corp/nockchain"
PROJECT_DIR="$HOME/nockchain"
ASSETS_DIR="$PROJECT_DIR/assets"
TMUX_SESSION="nockminer"
PUBKEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"
LOG_FILE="$PROJECT_DIR/miner.log"

# --- Step 0: System Dependencies ---
echo "[0/9] Installing system packages..."
sudo apt-get update
sudo apt-get install -y git build-essential curl tmux clang llvm-dev libclang-dev

# --- Step 1: Rust ---
echo "[1/9] Checking Rust..."
if ! command -v cargo &>/dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# --- Step 2: Clone repo ---
echo "[2/9] Cloning/updating nockchain repo..."
if [ ! -d "$PROJECT_DIR" ]; then
    git clone "$REPO_URL" "$PROJECT_DIR"
else
    cd "$PROJECT_DIR"
    git pull origin main || git pull origin master
fi

# --- Step 3: Create .jam kernel files ---
echo "[3/9] Creating dummy .jam kernel files..."
mkdir -p "$ASSETS_DIR"

cat > "$ASSETS_DIR/wal.jam" <<'EOF'
[%wallet %kernel [=seed ~[0xfa 0xce 0xbe 0xef]]]
EOF

cat > "$ASSETS_DIR/dumb.jam" <<'EOF'
[%dumb %kernel [=sample ~[100 200 300]]]
EOF

cat > "$ASSETS_DIR/miner.jam" <<'EOF'
[%miner %kernel [=nonce ~[1234 5678 9abc]]]
EOF

echo "[✔] .jam files created."

# --- Step 4: Optional Git commit ---
cd "$PROJECT_DIR"
if git rev-parse --is-inside-work-tree &>/dev/null; then
    # Unignore .jam if needed
    GITIGNORE="$PROJECT_DIR/.gitignore"
    if grep -q '\.jam' "$GITIGNORE"; then
        echo "[🔧] Removing .jam ignore rule from .gitignore"
        sed -i '/\.jam/d' "$GITIGNORE"
    fi

    git add -f assets/*.jam
    git commit -m "Add dummy kernel .jam files" || echo "ℹ️ No changes to commit."
    git push origin main || git push origin master || echo "⚠️ Git push failed (check branch)"
fi

# --- Step 5: Build ---
echo "[5/9] Building nockchain..."
cd "$PROJECT_DIR"
cargo build --release

# --- Step 6: Verify binaries ---
if [ ! -f "$PROJECT_DIR/target/release/nockchain" ]; then
    echo "❌ nockchain binary missing"
    exit 1
fi

if [ ! -f "$PROJECT_DIR/target/release/nockcli" ]; then
    echo "❌ nockcli binary missing"
    exit 1
fi

# --- Step 7: Start miner ---
echo "[6/9] Launching miner..."
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
tmux new-session -d -s "$TMUX_SESSION" "cd $PROJECT_DIR && ./target/release/nockchain --mine --mining-pubkey $PUBKEY | tee -a $LOG_FILE"

sleep 3

# --- Step 8: Wallet balance ---
echo "[7/9] Checking wallet balance..."
BALANCE=$($PROJECT_DIR/target/release/nockcli wallet balance 2>/dev/null || echo "Unavailable")
echo "Wallet Balance: $BALANCE"
echo "$(date): Wallet Balance: $BALANCE" >> "$LOG_FILE"

# --- Final ---
echo "🎉 Nockchain setup complete!"
echo "👉 To monitor miner: tmux attach -t $TMUX_SESSION"
