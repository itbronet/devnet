#!/bin/bash
set -euo pipefail

### CONFIG ###
REPO_URL="https://github.com/zorp-corp/nockchain"
PROJECT_DIR="$HOME/nockchain"
PUBKEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXiiAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"
ENV_FILE="$PROJECT_DIR/.env"
MAKEFILE="$PROJECT_DIR/Makefile"
TMUX_SESSION="nock-miner"
SERVICE_NAME="nock-miner"
BINARY_PATH="$PROJECT_DIR/target/release/nockchain"
SYSTEMD_SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
EMAIL="itbronet@gmail.com"

echo
echo "[+] Starting Nockchain Miner Setup"
echo "------------------------------------"

### 1. Rust toolchain installation ###
echo "[1/9] Checking Rust toolchain..."
if ! command -v cargo &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  export PATH="$HOME/.cargo/bin:$PATH"
else
  echo "Rust already installed."
fi

### 2. System dependencies ###
echo "[2/9] Installing system dependencies..."
sudo apt-get update -qq
sudo debconf-set-selections <<< "postfix postfix/main_mailer_type select Internet Site"
sudo debconf-set-selections <<< "postfix postfix/mailname string $(hostname -f)"
sudo apt-get install -y git make build-essential clang llvm-dev libclang-dev tmux postfix mailutils

### 3. Clone or update repo ###
echo "[3/9] Cloning or updating Nockchain repo..."
if [ ! -d "$PROJECT_DIR" ]; then
  git clone --depth 1 --branch master "$REPO_URL" "$PROJECT_DIR"
else
  cd "$PROJECT_DIR"
  git reset --hard HEAD
  git pull origin master
fi

cd "$PROJECT_DIR"

### 4. Write .env file ###
echo "[4/9] Writing .env file with your public key..."
cp -f .env_example .env
sed -i "s|^MINING_PUBKEY=.*|MINING_PUBKEY=$PUBKEY|" "$ENV_FILE"
echo "MINING_PUBKEY set to $PUBKEY"

### 5. Patch Makefile with pubkey ###
echo "[5/9] Patching Makefile with your public key..."
if grep -q "^export MINING_PUBKEY" "$MAKEFILE"; then
  sed -i "s|^export MINING_PUBKEY.*|export MINING_PUBKEY := $PUBKEY|" "$MAKEFILE"
else
  echo "export MINING_PUBKEY := $PUBKEY" >> "$MAKEFILE"
fi
grep "MINING_PUBKEY" "$MAKEFILE"

### 6. Build project ###
echo "[6/9] Building Nockchain..."
make install-hoonc
make build
make install-nockchain
make install-nockchain-wallet
make install-nockchain-miner
make install-nockchain-verifier

### 7. Clean old data directory ###
echo "[7/9] Cleaning old data directory..."
rm -rf "$PROJECT_DIR/.data.nockchain"

### 8. Create systemd service ###
echo "[8/9] Creating and enabling systemd service..."

SERVICE_CONTENT="[Unit]
Description=Nockchain Miner Service
After=network.target

[Service]
User=$(whoami)
WorkingDirectory=$PROJECT_DIR
ExecStart=$BINARY_PATH --mine --mining-pubkey $PUBKEY
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=$SERVICE_NAME

[Install]
WantedBy=multi-user.target
"

echo "$SERVICE_CONTENT" | sudo tee "$SYSTEMD_SERVICE_PATH" > /dev/null

sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME.service
sudo systemctl restart $SERVICE_NAME.service

### 9. Test service status and logs ###
echo "[9/9] Checking service status..."
sleep 5

SERVICE_STATUS=$(systemctl is-active $SERVICE_NAME.service)
if [ "$SERVICE_STATUS" == "active" ]; then
  echo "✅ $SERVICE_NAME service is active and running."
else
  echo "❌ $SERVICE_NAME service is NOT running. Check logs with: sudo journalctl -u $SERVICE_NAME.service -f"
  exit 1
fi

echo "To view live miner logs: sudo journalctl -u $SERVICE_NAME.service -f"

echo
echo "Setup complete! Miner is running as a systemd service."
echo

exit 0
