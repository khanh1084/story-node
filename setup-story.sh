#!/bin/bash

# Update and install necessary packages
sudo apt-get update -y
sudo apt-get install -y curl git make jq build-essential gcc unzip wget lz4 aria2
sudo apt-get update -y && sudo apt-get upgrade -y

# Download and extract geth
wget https://story-geth-binaries.s3.us-west-1.amazonaws.com/geth-public/geth-linux-amd64-0.9.3-b224fdf.tar.gz
tar -xzvf geth-linux-amd64-0.9.3-b224fdf.tar.gz
[ ! -d "$HOME/go/bin" ] && mkdir -p $HOME/go/bin
if ! grep -q "$HOME/go/bin" $HOME/.bash_profile; then
  echo 'export PATH=$PATH:$HOME/go/bin' >> $HOME/.bash_profile
fi
sudo rm -f geth-linux-amd64-0.9.3-b224fdf.tar.gz
sudo cp geth-linux-amd64-0.9.3-b224fdf/geth $HOME/go/bin/story-geth
source $HOME/.bash_profile
story-geth version

# Download and extract story
wget https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.10.1-57567e5.tar.gz
tar -xzvf story-linux-amd64-0.10.1-57567e5.tar.gz
[ ! -d "$HOME/go/bin" ] && mkdir -p $HOME/go/bin
if ! grep -q "$HOME/go/bin" $HOME/.bash_profile; then
  echo 'export PATH=$PATH:$HOME/go/bin' >> $HOME/.bash_profile
fi
sudo rm -f story-linux-amd64-0.10.1-57567e5.tar.gz
sudo cp story-linux-amd64-0.10.1-57567e5/story $HOME/go/bin/story
source $HOME/.bash_profile
sudo rm -f /usr/bin/story
sudo ln -sf $HOME/go/bin/story /usr/local/bin/story
story version

# Initialize story
story init --network iliad --force

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
sudo apt-get install wget lz4 aria2 pv -y

# Download snapshots
aria2c -x 16 -s 16 https://snapshots.mandragora.io/geth_snapshot.lz4
aria2c -x 16 -s 16 https://snapshots.mandragora.io/story_snapshot.lz4

# Stop services before applying snapshots
sudo systemctl stop story-geth
sudo systemctl stop story

# Backup and remove old data
mv $HOME/.story/story/data/priv_validator_state.json $HOME/.story/priv_validator_state.json.backup
rm -rf ~/.story/story/data
rm -rf ~/.story/geth/iliad/geth/chaindata

# Extract snapshots
lz4 -c -d geth_snapshot.lz4 | tar -x -C $HOME/.story/geth/iliad/geth
lz4 -c -d story_snapshot.lz4 | tar -x -C $HOME/.story/story

# Clean up snapshot files
sudo mkdir -p /root/.story/story/data
lz4 -d story_snapshot.lz4 | pv | sudo tar xv -C /root/.story/story/
sudo mkdir -p /root/.story/geth/iliad/geth/chaindata
lz4 -d geth_snapshot.lz4 | pv | sudo tar xv -C /root/.story/geth/iliad/geth/

# Restore validator state
mv $HOME/.story/priv_validator_state.json.backup $HOME/.story/story/data/priv_validator_state.json

# Start services
sudo systemctl start story-geth
sudo systemctl start story

sudo rm -rf story_snapshot.lz4
sudo rm -rf geth_snapshot.lz4

# Export and create validator
story validator export --export-evm-key
cat /root/.story/story/config/private_key.txt
story validator export --export-evm-key --evm-key-path .env
