#!/bin/bash
set -euo pipefail

REPO_URL="https://github.com/zorp-corp/nockchain.git"
REPO_DIR="$HOME/nockchain"
ASSET_DIR="$REPO_DIR/assets"
TMUX_SESSION="nock-miner"
MINING_PUBKEY="YOUR_PUBKEY_HERE"  # <-- Replace this with your real mining pubkey

echo "[1/9] Installing Rust toolchain if missing..."
if ! command -v cargo &> /dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
fi

echo "[2/9] Cloning or updating nockchain repo..."
if [ -d "$REPO_DIR/.git" ]; then
  cd "$REPO_DIR"
  git fetch origin
  git checkout master
  git reset --hard origin/master
  git pull origin master
else
  git clone --branch master "$REPO_URL" "$REPO_DIR"
fi

echo "[3/9] Creating assets directory and .jam kernel files..."
mkdir -p "$ASSET_DIR"

cat > "$ASSET_DIR/wal.jam" <<'EOF'
/-  *core

|=  [state=map _ b]
=+  new-state
  (merge state
    [%balance (add (get %balance state 0) b)]
  )
^-  map _ b
(new-state)
EOF

cat > "$ASSET_DIR/miner.jam" <<'EOF'
/-  *core

|=  state=map _ b
=+  new-state
  (merge state
    [%mining true]
  )
^-  map _ b
(new-state)
EOF

cat > "$ASSET_DIR/dumb.jam" <<'EOF'
/-  *core

|=  state=map _ b
=+  new-state
  (merge state
    [%status 'idle']
  )
^-  map _ b
(new-state)
EOF

echo "[4/9] Adding and committing .jam files to git (force adding to override .gitignore)..."
cd "$REPO_DIR"
git add -f assets/wal.jam assets/miner.jam assets/dumb.jam
if git diff --cached --quiet; then
  echo "No changes in .jam files to commit."
else
  git commit -m "Add/update .jam kernel files"
  git push origin master
fi

echo "[5/9] Building nockchain release..."
cargo build --release --manifest-path "$REPO_DIR/Cargo.toml"

echo "[6/9] Killing any existing tmux session named $TMUX_SESSION..."
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

echo "[7/9] Starting miner in tmux session $TMUX_SESSION..."
tmux new-session -d -s "$TMUX_SESSION" bash -c "
  cd $REPO_DIR &&
  ./target/release/nockchain --mine $MINING_PUBKEY 2>&1 | tee -a miner.log
"

echo "[8/9] Miner started inside tmux session: $TMUX_SESSION"
echo "You can attach using: tmux attach -t $TMUX_SESSION"

echo "[9/9] Setup complete."
