#!/bin/bash

# Update and install necessary packages
sudo apt-get update -y
sudo apt-get install -y curl git make jq build-essential gcc unzip wget lz4 aria2
sudo apt-get update -y && sudo apt-get upgrade -y

# Download and extract geth
wget https://story-geth-binaries.s3.us-west-1.amazonaws.com/geth-public/geth-linux-amd64-0.9.2-ea9f0d2.tar.gz
tar -xzvf geth-linux-amd64-0.9.2-ea9f0d2.tar.gz
[ ! -d "$HOME/go/bin" ] && mkdir -p $HOME/go/bin
if ! grep -q "$HOME/go/bin" $HOME/.bash_profile; then
  echo 'export PATH=$PATH:$HOME/go/bin' >> $HOME/.bash_profile
fi
sudo cp geth-linux-amd64-0.9.2-ea9f0d2/geth $HOME/go/bin/story-geth
source $HOME/.bash_profile
story-geth version

# Download and extract story
wget https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.9.11-2a25df1.tar.gz
tar -xzvf story-linux-amd64-0.9.11-2a25df1.tar.gz
[ ! -d "$HOME/go/bin" ] && mkdir -p $HOME/go/bin
if ! grep -q "$HOME/go/bin" $HOME/.bash_profile; then
  echo 'export PATH=$PATH:$HOME/go/bin' >> $HOME/.bash_profile
fi
sudo cp story-linux-amd64-0.9.11-2a25df1/story $HOME/go/bin/story
source $HOME/.bash_profile
story version

# Initialize story
story init --network iliad

# Create systemd service for story-geth
sudo tee /etc/systemd/system/story-geth.service > /dev/null <<EOF
[Unit]
Description=Story Geth Client
After=network.target

[Service]
User=root
ExecStart=/root/go/bin/story-geth --iliad --syncmode full
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service for story
sudo tee /etc/systemd/system/story.service > /dev/null <<EOF
[Unit]
Description=Story Consensus Client
After=network.target

[Service]
User=root
ExecStart=/root/go/bin/story run
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

# Start and enable services
sudo systemctl daemon-reload
sudo systemctl start story-geth
sudo systemctl enable story-geth

sudo systemctl start story
sudo systemctl enable story

# Update persistent peers
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$(curl -sS https://story-testnet-rpc.polkachu.com/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr)"' | awk -F ':' '{print $1":"$(NF)}' | paste -sd, -)\"/" $HOME/.story/story/config/config.toml

# Restart services
sudo systemctl restart story
sudo systemctl restart story-geth

# Stop services for snapshot
sudo systemctl stop story
sudo systemctl stop story-geth

# Install additional packages
sudo apt-get install wget lz4 -y

# Download snapshots
wget -O geth_snapshot.lz4 https://snapshots.mandragora.io/geth_snapshot.lz4
wget -O story_snapshot.lz4 https://snapshots.mandragora.io/story_snapshot.lz4

# Stop services before applying snapshots
sudo systemctl stop story-geth
sudo systemctl stop story

# Backup and remove old data
sudo cp $HOME/.story/story/data/priv_validator_state.json $HOME/.story/priv_validator_state.json.backup
sudo rm -rf $HOME/.story/geth/iliad/geth/chaindata
sudo rm -rf $HOME/.story/story/data

# Extract snapshots
lz4 -c -d geth_snapshot.lz4 | tar -x -C $HOME/.story/geth/iliad/geth
lz4 -c -d story_snapshot.lz4 | tar -x -C $HOME/.story/story

# Clean up snapshot files
sudo rm -v geth_snapshot.lz4
sudo rm -v story_snapshot.lz4

# Restore validator state
sudo cp $HOME/.story/priv_validator_state.json.backup $HOME/.story/story/data/priv_validator_state.json

# Start services
sudo systemctl start story-geth
sudo systemctl start story

# Export and create validator
story validator export --export-evm-key
story validator create --stake 1000000000000000000