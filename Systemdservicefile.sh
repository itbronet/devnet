[Unit]
Description=Nockchain Miner Service
After=network.target

[Service]
User=YOUR_USERNAME
WorkingDirectory=/home/YOUR_USERNAME/nockchain
ExecStart=/home/YOUR_USERNAME/nockchain/target/release/nockchain --mine --mining-pubkey 35TRFiYFy3GbwKV5eKriYA8AevHQpv9iuvCcgj46oKWpidJVJcNLFrAXiiAoU3ZDg8XuGwApdLKTT3EshcMxMNfEsvtMd1YkRVrvjc5dMhdSAHMyk6dkFxvsaMBa2R
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=nock-miner

[Install]
WantedBy=multi-user.target
