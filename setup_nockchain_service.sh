#!/bin/bash
set -euo pipefail

USERNAME=$(whoami)
SERVICE_PATH="/etc/systemd/system/nock-miner.service"
PROJECT_DIR="/home/$USERNAME/nockchain"
PUBKEY="35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXiiAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R"
BINARY_PATH="$PROJECT_DIR/target/release/nockchain"

if [ ! -f "$BINARY_PATH" ]; then
  echo "Error: Nockchain binary not found at $BINARY_PATH"
  exit 1
fi

echo "Creating systemd service file at $SERVICE_PATH..."

sudo tee "$SERVICE_PATH" > /dev/null <<EOF
[Unit]
Description=Nockchain Miner Service
After=network.target

[Service]
User=$USERNAME
WorkingDirectory=$PROJECT_DIR
ExecStart=$BINARY_PATH --mine --mining-pubkey $PUBKEY
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=nock-miner

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "Enabling and starting nock-miner service..."
sudo systemctl enable nock-miner.service
sudo systemctl start nock-miner.service

echo "Service status:"
sudo systemctl status nock-miner.service --no-pager

echo "You can view logs via: sudo journalctl -u nock-miner.service -f"
