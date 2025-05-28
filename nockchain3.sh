#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/nockchain_install.log"
ASSET_DIR="/root/assets"
REPO_URL="https://github.com/zorp-corp/nockchain.git"
REPO_DIR="/root/nockchain"
EMAIL="itbronet@gmail.com"
SESSION_NAME="nockminer"
CRON_TAG="# Nockchain Auto-Restart"

log() {
    echo "[✔] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    echo "[✘] $1" | tee -a "$LOG_FILE"
    exit 1
}

install_dependencies() {
    log "Installing dependencies..."
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl git tmux postfix mailutils build-essential pkg-config libssl-dev clang cmake || error_exit "Failed to install dependencies"
    echo "postfix postfix/mailname string localhost" | debconf-set-selections
    echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections
    dpkg-reconfigure -f noninteractive postfix || log "Postfix may have been already configured"
}

setup_rust() {
    log "Setting up Rust..."
    if ! command -v rustc &>/dev/null; then
        curl https://sh.rustup.rs -sSf | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
    rustup update
}

clone_or_update_repo() {
    log "Cloning or updating Nockchain repo..."
    if [ -d "$REPO_DIR" ]; then
        cd "$REPO_DIR" && git pull origin master
    else
        git clone "$REPO_URL" "$REPO_DIR"
    fi
}

create_assets() {
    log "Ensuring .jam assets exist..."
    mkdir -p "$ASSET_DIR"
    for file in wal.jam miner.jam dumb.jam; do
        path="$ASSET_DIR/$file"
        if [ ! -f "$path" ]; then
            echo "0" > "$path"
            log "Created $file with dummy content"
        fi
    done
    ln -sf "$ASSET_DIR" "$REPO_DIR/assets"
}

build_nockchain() {
    log "Building Nockchain..."
    cd "$REPO_DIR"
    cargo build --release || error_exit "Build failed"
    cargo check --release || error_exit "Build check failed"
    ./target/release/nockchain --help > /dev/null || error_exit "Binary did not run correctly"
}

launch_miner_tmux() {
    log "Launching miner in tmux..."
    cd "$REPO_DIR"
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    tmux new-session -d -s "$SESSION_NAME" "./target/release/nockchain > miner.log 2>&1"
    sleep 5
    if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        error_exit "Failed to start miner in tmux"
    fi
}

setup_alerts() {
    log "Setting up block mining alerts..."
    alert_script="/root/nockchain/block-alert.sh"
    cat <<EOF > "$alert_script"
#!/bin/bash
tail -Fn0 /root/nockchain/miner.log | \\
grep --line-buffered "block by-height" | \\
while read -r line; do
    echo "New block mined: \$line" | mail -s "Nockchain Mined a Block" "$EMAIL"
done
EOF
    chmod +x "$alert_script"
    tmux kill-session -t alertmon 2>/dev/null || true
    tmux new-session -d -s alertmon "bash $alert_script"
}

setup_cron_reboot() {
    log "Adding cron for auto-restart after reboot..."
    crontab -l | grep -v "$CRON_TAG" > /tmp/crontab.new || true
    echo "@reboot bash $REPO_DIR/nockchain.sh $CRON_TAG" >> /tmp/crontab.new
    crontab /tmp/crontab.new && rm /tmp/crontab.new
}

final_test() {
    log "Performing final validation..."
    if ! ps aux | grep "[n]ockchain" > /dev/null; then
        error_exit "Nockchain miner not running"
    fi

    if [ ! -s "$REPO_DIR/miner.log" ]; then
        error_exit "Miner log not being generated"
    fi

    grep -q "block by-height" "$REPO_DIR/miner.log" && \
    log "Miner already mined at least one block!" || \
    log "Miner running. Awaiting block..."
}

main() {
    install_dependencies
    setup_rust
    clone_or_update_repo
    create_assets
    build_nockchain
    launch_miner_tmux
    setup_alerts
    setup_cron_reboot
    final_test
    log "Nockchain miner setup complete and validated ✅"
}

main
