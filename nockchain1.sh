#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# User-configurable variables
REPO_URL="https://github.com/zorp-corp/nockchain.git"
REPO_DIR="$HOME/nockchain"
SOCKET_DIR="$REPO_DIR/.socket"
SOCKET_FILE="$SOCKET_DIR/nockchain.sock"
PUBLIC_KEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXii1hT6giAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"
TMUX_SESSION="nockminer"
LOG_FILE="$REPO_DIR/nockminer.log"

# Paths for Assets and jam files - user can customize here
ASSETS_SRC_DIR="$HOME/nockchain_assets"
WAL_JAM_SRC="$HOME/nockchain_assets/wal.jam"
MINER_JAM_SRC="$HOME/nockchain_assets/miner.jam"
DUMB_JAM_SRC="$HOME/nockchain_assets/dumb.jam"

function log() {
    echo "[$(date -Is)] $*"
}

function ensure_pkg_installed() {
    local pkg=$1
    if ! dpkg -s "$pkg" &>/dev/null; then
        log "Installing missing package: $pkg"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y "$pkg"
    else
        log "Package $pkg already installed."
    fi
}

function fix_mail_install_freeze() {
    # Fix freezes in mail packages configuration
    log "Checking for and fixing mail config freezes..."
    # Send default config to postfix to bypass prompts
    echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections
    echo "postfix postfix/mailname string 'localhost'" | debconf-set-selections
    # Pre-configure postfix to avoid interactive prompts
    DEBIAN_FRONTEND=noninteractive apt-get install -y postfix mailutils || true
}

function install_prerequisites() {
    log "Installing prerequisites..."
    local pkgs=(curl git build-essential tmux mailutils postfix)
    for pkg in "${pkgs[@]}"; do
        ensure_pkg_installed "$pkg"
    done
    fix_mail_install_freeze
}

function install_rust() {
    if ! command -v rustc &>/dev/null; then
        log "Rust not found. Installing Rust..."
        curl https://sh.rustup.rs -sSf | sh -s -- -y
        source "$HOME/.cargo/env"
    else
        log "Rust is already installed."
    fi
}

function clone_or_update_repo() {
    if [ -d "$REPO_DIR/.git" ]; then
        log "Repository already cloned. Pulling latest changes..."
        git -C "$REPO_DIR" pull --rebase || log "Git pull failed, continuing..."
    else
        log "Cloning repository..."
        git clone "$REPO_URL" "$REPO_DIR"
    fi
}

function build_nockchain() {
    log "Building Nockchain project..."
    cd "$REPO_DIR"
    cargo clean || true
    cargo build --release
}

function clean_stale_socket() {
    if [ -S "$SOCKET_FILE" ]; then
        log "Socket file exists: $SOCKET_FILE"
        # Check if any process is using the socket
        if ! lsof -n "$SOCKET_FILE" &>/dev/null; then
            log "Socket is stale, removing..."
            rm -f "$SOCKET_FILE"
        else
            log "Socket is active."
        fi
    else
        log "Socket file does not exist yet."
    fi
}

function create_assets_and_jams() {
    log "Checking Assets folder and .jam files..."

    mkdir -p "$REPO_DIR"

    # Assets folder
    if [ -d "$ASSETS_SRC_DIR" ]; then
        if [ ! -d "$REPO_DIR/Assets" ]; then
            log "Copying Assets folder from $ASSETS_SRC_DIR"
            cp -r "$ASSETS_SRC_DIR" "$REPO_DIR/Assets"
        else
            log "Assets folder already exists."
        fi
    else
        if [ ! -d "$REPO_DIR/Assets" ]; then
            log "Assets source folder not found. Creating empty Assets folder."
            mkdir -p "$REPO_DIR/Assets"
        else
            log "Assets folder already exists."
        fi
    fi

    # jam files list
    declare -A jams=(
        ["wal.jam"]="$WAL_JAM_SRC"
        ["miner.jam"]="$MINER_JAM_SRC"
        ["dumb.jam"]="$DUMB_JAM_SRC"
    )

    for jamfile in "${!jams[@]}"; do
        local src="${jams[$jamfile]}"
        local dest="$REPO_DIR/$jamfile"

        if [ -f "$src" ]; then
            if [ ! -f "$dest" ]; then
                log "Copying $jamfile from $src"
                cp "$src" "$dest"
            else
                log "$jamfile already exists."
            fi
        else
            if [ ! -f "$dest" ]; then
                log "Source $jamfile not found. Creating placeholder $jamfile"
                echo "# Placeholder $jamfile" > "$dest"
            else
                log "$jamfile already exists."
            fi
        fi
    done
}

function start_tmux_session() {
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        log "Tmux session $TMUX_SESSION already running."
    else
        log "Starting new tmux session $TMUX_SESSION"
        tmux new-session -d -s "$TMUX_SESSION" \
          "cd $REPO_DIR && cargo run --bin nockchain --release > $LOG_FILE 2>&1"
        sleep 3
    fi
}

function check_nockchain_running() {
    if pgrep -f "cargo run --bin nockchain" &>/dev/null; then
        log "Nockchain process is running."
        return 0
    else
        log "Nockchain process is NOT running."
        return 1
    fi
}

function send_email_alert() {
    local subject="$1"
    local body="$2"
    log "Sending email alert: $subject"
    echo -e "$body" | mail -s "$subject" "itbronet@gmail.com" || log "Failed to send email alert."
}

function monitor_logs_for_alerts() {
    log "Starting background log monitor for alerts..."
    local alert_keywords=("crash" "error" "fail" "panic" "block mined")
    (
        tail -Fn0 "$LOG_FILE" | while read -r line; do
            for keyword in "${alert_keywords[@]}"; do
                if echo "$line" | grep -iq "$keyword"; then
                    send_email_alert "Nockchain Alert: $keyword detected" "$line"
                fi
            done
        done
    ) &
    # Store PID to file for future killing if needed
    echo $! > "$REPO_DIR/log_monitor.pid"
}

function main() {
    log "=== Starting nockchain.sh setup ==="

    # Step 1: Install required packages & fix mail config freezes
    install_prerequisites

    # Step 2: Install Rust if missing
    install_rust

    # Step 3: Clone or update repo
    clone_or_update_repo

    # Step 4: Build the project
    build_nockchain

    # Step 5: Clean stale socket if any
    clean_stale_socket

    # Step 6: Create or verify Assets folder and jam files
    create_assets_and_jams

    # Step 7: Start or verify tmux session running nockchain node
    start_tmux_session

    # Step 8: Start background log monitoring for alerts if not already running
    if [ ! -f "$REPO_DIR/log_monitor.pid" ] || ! kill -0 $(cat "$REPO_DIR/log_monitor.pid") 2>/dev/null; then
        monitor_logs_for_alerts
    else
        log "Log monitor already running."
    fi

    # Step 9: Final status
    if check_nockchain_running; then
        log "Nockchain node running successfully."
        log "Your public key is: $PUBLIC_KEY"
    else
        log "WARNING: Nockchain node is not running. Check logs for details."
    fi

    log "=== Setup complete ==="
}

main "$@"
