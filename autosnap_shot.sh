#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/itrocket-team/testnet_guides/main/utils/common.sh)

printLogo
echo "Story Snapshot Automation Tool"
sleep 1

# Defining variables for type and project
type=testnet
project=story
rootUrl=server-3.itrocket.net
storyPath=$HOME/.story/story
gethPath=$HOME/.story/geth/iliad/geth
# Variables for file servers and parent RPCs
FILE_SERVERS=(
  "https://server-3.itrocket.net/testnet/story/.current_state.json"
  "https://server-1.itrocket.net/testnet/story/.current_state.json"
  "https://server-5.itrocket.net/testnet/story/.current_state.json"
)
RPC_COMBINED_FILE="https://server-3.itrocket.net/testnet/story/.rpc_combined.json"
PARENT_RPC="https://story-testnet-rpc.itrocket.net"
MAX_ATTEMPTS=3
TEST_FILE_SIZE=50000000  # File size in bytes for download speed check

function printLogo {
  bash <(curl -s https://raw.githubusercontent.com/itrocket-team/testnet_guides/main/utils/logo.sh)
}

printGreen "1. Installing dependencies..." && sleep 1

sudo apt update && sudo apt upgrade -y
sudo apt install curl git wget htop tmux jq make lz4 unzip bc -y

# Array to store available snapshots
SNAPSHOTS=()

# Function to get the server number from the URL
get_server_number() {
  local URL=$1
  echo "$URL" | grep -oP 'server-\K[0-9]+'
}

# Function to prompt user to continue or exit
ask_to_continue() {
  read -p "$(printYellow 'Do you want to continue anyway? (y/n): ')" choice
  if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    printRed "Exiting script."
    exit 1
  fi
}

# Function to fetch snapshot data from the server
fetch_snapshot_data() {
  local URL=$1
  local ATTEMPT=0
  local DATA=""

  while (( ATTEMPT < MAX_ATTEMPTS )); do
    DATA=$(curl -s --max-time 5 "$URL")
    if [[ -n "$DATA" ]]; then
      break
    else
      ((ATTEMPT++))
      sleep 1
    fi
  done

  echo "$DATA"
}

# Function to get the second Parent RPC from the file
get_second_parent_rpc() {
  local RPC_RESPONSE=$(curl -s --max-time 5 "$RPC_COMBINED_FILE")
  if [[ -n "$RPC_RESPONSE" ]]; then
    echo $(echo "$RPC_RESPONSE" | jq -r 'to_entries[0].key')
  else
    echo ""
  fi
}

# Function to get the maximum block height from parent RPCs
get_parent_block_height() {
  local MAX_PARENT_HEIGHT=0
  for ((ATTEMPTS=0; ATTEMPTS<MAX_ATTEMPTS; ATTEMPTS++)); do

    local PARENT_HEIGHTS=()
    for RPC in "$PARENT_RPC" "$SECOND_PARENT_RPC"; do
      if [[ -n "$RPC" ]]; then
        local RESPONSE=$(curl -s --max-time 3 "$RPC/status")
        local HEIGHT=$(echo "$RESPONSE" | jq -r '.result.sync_info.latest_block_height' | tr -d '[:space:]')
        if [[ $HEIGHT =~ ^[0-9]+$ ]]; then
          PARENT_HEIGHTS+=("$HEIGHT")
        fi
      fi
    done

    if [[ ${#PARENT_HEIGHTS[@]} -gt 0 ]]; then
      MAX_PARENT_HEIGHT=$(printf "%s\n" "${PARENT_HEIGHTS[@]}" | sort -nr | head -n1)
      break
    fi

    sleep 5
  done
  echo $MAX_PARENT_HEIGHT
}

# Function to get block time by height
get_block_time() {
  local HEIGHT=$1
  local RPC_URLS=("$PARENT_RPC" "$SECOND_PARENT_RPC")
  for RPC_URL in "${RPC_URLS[@]}"; do
    if [[ -n "$RPC_URL" ]]; then
      local RESPONSE=$(curl -s --max-time 5 "$RPC_URL/block?height=$HEIGHT")
      if [[ -n "$RESPONSE" ]]; then
        local BLOCK_TIME=$(echo "$RESPONSE" | jq -r '.result.block.header.time')
        if [[ "$BLOCK_TIME" != "null" ]]; then
          echo "$BLOCK_TIME"
          return 0
        fi
      fi
    fi
  done
  echo ""
}

# Function to measure download speed from a specific server
measure_download_speed() {
  local SERVER_URL=$1
  local SNAPSHOT_NAME=$2
  local TOTAL_SPEED=0
  local NUM_TESTS=3

  for ((i=1; i<=NUM_TESTS; i++)); do
    local TMP_FILE=$(mktemp)
    local FULL_URL="$SERVER_URL/${type}/${project}/$SNAPSHOT_NAME"

    local START_TIME=$(date +%s.%N)
    curl -s --max-time 10 --range 0-$TEST_FILE_SIZE -o "$TMP_FILE" "$FULL_URL"
    local END_TIME=$(date +%s.%N)

    local DURATION=$(echo "$END_TIME - $START_TIME" | bc -l)
    if (( $(echo "$DURATION > 0" | bc -l) )); then
      local SPEED=$(echo "scale=2; $TEST_FILE_SIZE / $DURATION" | bc -l)
      TOTAL_SPEED=$(echo "$TOTAL_SPEED + $SPEED" | bc -l)
    fi

    rm -f "$TMP_FILE"
  done

  if (( $(echo "$TOTAL_SPEED > 0" | bc -l) )); then
    local AVERAGE_SPEED=$(echo "scale=2; $TOTAL_SPEED / $NUM_TESTS" | bc -l)
  else
    local AVERAGE_SPEED=0
  fi

  echo "$AVERAGE_SPEED"
}

# Function to calculate estimated download time
calculate_estimated_time() {
  local FILE_SIZE_BYTES=$1
  local DOWNLOAD_SPEED=$2  # In bytes per second
  if (( $(echo "$DOWNLOAD_SPEED > 0" | bc -l) )); then
    local TIME_SECONDS=$(echo "scale=2; $FILE_SIZE_BYTES / $DOWNLOAD_SPEED" | bc -l)
    local TIME_SECONDS_INT=$(printf "%.0f" "$TIME_SECONDS")
    local TIME_HOURS=$((TIME_SECONDS_INT / 3600))
    local TIME_MINUTES=$(( (TIME_SECONDS_INT % 3600) / 60 ))
    echo "${TIME_HOURS}h ${TIME_MINUTES}m"
  else
    echo "N/A"
  fi
}

# Function to display snapshot information
process_snapshot_info() {
  local SERVER_NAME=$1
  local DATA=$2
  local PARENT_BLOCK_HEIGHT=$3
  local SERVER_URL=$4

  if [[ -n "$DATA" ]]; then
    local SNAPSHOT_NAME=$(echo "$DATA" | jq -r '.snapshot_name')
    local GETH_NAME=$(echo "$DATA" | jq -r '.snapshot_geth_name')
    local SNAPSHOT_HEIGHT=$(echo "$DATA" | jq -r '.snapshot_height')
    local SNAPSHOT_SIZE=$(echo "$DATA" | jq -r '.snapshot_size')
    local GETH_SIZE=$(echo "$DATA" | jq -r '.geth_snapshot_size')
    local INDEXER=$(echo "$DATA" | jq -r '.indexer')

    local SNAPSHOT_SIZE_BYTES=$(echo "$SNAPSHOT_SIZE" | sed 's/G//')000000000
    local GETH_SIZE_BYTES=$(echo "$GETH_SIZE" | sed 's/G//')000000000
    local TOTAL_SIZE_BYTES=$(($SNAPSHOT_SIZE_BYTES + $GETH_SIZE_BYTES))

    local TOTAL_SIZE_GB_NUM=$(echo "$TOTAL_SIZE_BYTES / 1000000000" | bc)
    local TOTAL_SIZE_GB="${TOTAL_SIZE_GB_NUM}G"

    local DOWNLOAD_SPEED=$(measure_download_speed "$SERVER_URL" "$SNAPSHOT_NAME")
    local ESTIMATED_TIME=$(calculate_estimated_time "$TOTAL_SIZE_BYTES" "$DOWNLOAD_SPEED")

    local BLOCKS_BEHIND=$((PARENT_BLOCK_HEIGHT - SNAPSHOT_HEIGHT))

    local SNAPSHOT_TYPE="pruned"
    if [[ "$INDEXER" == "kv" ]]; then
      SNAPSHOT_TYPE="archive"
    fi

    # Get block time for SNAPSHOT_HEIGHT
    local BLOCK_TIME=$(get_block_time "$SNAPSHOT_HEIGHT")
    local SNAPSHOT_AGE=""
    if [[ -n "$BLOCK_TIME" ]]; then
      local BLOCK_TIME_EPOCH=$(date -d "$BLOCK_TIME" +%s)
      local CURRENT_TIME_EPOCH=$(date +%s)
      local TIME_DIFF=$((CURRENT_TIME_EPOCH - BLOCK_TIME_EPOCH))
      local TIME_DIFF_HOURS=$((TIME_DIFF / 3600))
      local TIME_DIFF_MINUTES=$(((TIME_DIFF % 3600) / 60))
      SNAPSHOT_AGE="${TIME_DIFF_HOURS}h ${TIME_DIFF_MINUTES}m ago"
    else
      SNAPSHOT_AGE="N/A"
    fi

    local SERVER_NUMBER=$(get_server_number "$SERVER_URL")
    SNAPSHOTS+=("$SERVER_NUMBER|$SNAPSHOT_TYPE|$SNAPSHOT_HEIGHT|$BLOCKS_BEHIND|$SNAPSHOT_AGE|$TOTAL_SIZE_GB|$SNAPSHOT_SIZE|$GETH_SIZE|$ESTIMATED_TIME|$SERVER_URL|$SNAPSHOT_NAME|$GETH_NAME")
  fi
}

# Function to install the selected snapshot
install_snapshot() {
  local SNAPSHOT_NAME=$1
  local GETH_NAME=$2
  local SERVER_URL=$3

  echo "Installing snapshot from $SERVER_URL:"
  echo "Snapshot: $SNAPSHOT_NAME"
  echo "Geth Snapshot: $GETH_NAME"

  printLine
  printGreen "3.  Stopping story and story-geth..." && sleep 1
  if sudo systemctl stop story story-geth; then
    printBlue "done"
  else
    printRed "Failed to stop services"
    ask_to_continue
  fi

  printLine
  printGreen "4.  Backing up priv_validator_state.json..." && sleep 1
  if cp "$storyPath/data/priv_validator_state.json" "$storyPath/priv_validator_state.json.backup"; then
    printBlue "done"
  else
    printRed "Failed to backup priv_validator_state.json"
    ask_to_continue
  fi

  printLine
  printGreen "5.  Removing old data and unpacking Story snapshot..." && sleep 1
  if rm -rf "$storyPath/data"; then
    printBlue "Old data removed"
  else
    printRed "Failed to remove old data"
    ask_to_continue
  fi

  printLine
  if curl "$SERVER_URL/${type}/${project}/$SNAPSHOT_NAME" | lz4 -dc - | tar -xf - -C "$storyPath"; then
    printBlue "Snapshot unpacked"
  else
    printRed "Failed to unpack Story snapshot"
    ask_to_continue
  fi

  printLine
  printGreen "6.  Restoring priv_validator_state.json..." && sleep 1
  if mv "$storyPath/priv_validator_state.json.backup" "$storyPath/data/priv_validator_state.json"; then
    printBlue "done"
  else
    printRed "Failed to restore priv_validator_state.json"
    ask_to_continue
  fi

  printLine
  printGreen "7.  Deleting geth data and unpacking geth snapshot..." && sleep 1
  if rm -rf "$gethPath/chaindata"; then
    printBlue "Geth data deleted"
  else
    printRed "Failed to delete geth data"
    ask_to_continue
  fi

  printLine
  if curl "$SERVER_URL/${type}/${project}/$GETH_NAME" | lz4 -dc - | tar -xf - -C "$gethPath"; then
    printBlue "Geth snapshot unpacked"
  else
    printRed "Failed to unpack geth snapshot"
    ask_to_continue
  fi

  printLine
  printGreen "8.  Starting Story and Geth services..." && sleep 1
  if sudo systemctl restart story story-geth; then
    printBlue "done"
  else
    printRed "Failed to start services"
    ask_to_continue
  fi

  printLine
  printGreen "9.  Checking Sync status after 1m, please wait..." && sleep 1m

  rpc_port=$(grep -m 1 -oP '^laddr = "\K[^"]+' "$storyPath/config/config.toml" | cut -d ':' -f 3)
  while true; do
    local_height=$(curl -s localhost:$rpc_port/status | jq -r '.result.sync_info.latest_block_height')
    network_height=$(curl -s $PARENT_RPC/status | jq -r '.result.sync_info.latest_block_height')

    if ! [[ "$local_height" =~ ^[0-9]+$ ]] || ! [[ "$network_height" =~ ^[0-9]+$ ]]; then
      echo -e "\033[1;31mError: Invalid block height data. Retrying...\033[0m"
      sleep 5
      continue
    fi

    blocks_left=$((network_height - local_height))
    if [ "$blocks_left" -lt 0 ]; then
      blocks_left=0
    fi

    echo -e "\033[1;33mYour Node Height:\033[1;34m $local_height\033[0m \033[1;33m| Network Height:\033[1;36m $network_height\033[0m \033[1;33m| Blocks Left:\033[1;31m $blocks_left\033[0m"

    sleep 5
  done
}

# Function to display spinner
spinner() {
  local delay=0.1
  local spinstr='|/-\'
  while [ -f /tmp/snapshot_processing ]; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\r"
  done
}

printGreen "2. Searching snapshots and calculating parameters..." && sleep 1
printLine

# Create flag file to indicate process
touch /tmp/snapshot_processing
spinner &
SPINNER_PID=$!

# Fetch second Parent RPC
SECOND_PARENT_RPC=$(get_second_parent_rpc)

# Get block heights from Parent RPCs
MAX_PARENT_HEIGHT=$(get_parent_block_height)

# Check for snapshot data on servers
for FILE_SERVER in "${FILE_SERVERS[@]}"; do
  DATA=$(fetch_snapshot_data "$FILE_SERVER")
  if [[ -n "$DATA" ]]; then
    SERVER_URL=$(echo "$FILE_SERVER" | sed "s|/${type}/${project}/.current_state.json||")
    SERVER_NUMBER=$(get_server_number "$SERVER_URL")
    process_snapshot_info "$SERVER_NUMBER" "$DATA" "$MAX_PARENT_HEIGHT" "$SERVER_URL"
  fi
done

# Remove flag file and stop spinner
rm -f /tmp/snapshot_processing
wait $SPINNER_PID 2>/dev/null
echo

# If no servers were available
if [[ ${#SNAPSHOTS[@]} -eq 0 ]]; then
  echo "Sorry, snapshot is not available at the moment. Please try later."
  exit 1
fi

# Display available snapshots with information
printGreen "Available snapshots:"
printLine
for i in "${!SNAPSHOTS[@]}"; do
  IFS='|' read -r SERVER_NUMBER SNAPSHOT_TYPE SNAPSHOT_HEIGHT BLOCKS_BEHIND SNAPSHOT_AGE TOTAL_SIZE_GB SNAPSHOT_SIZE GETH_SIZE ESTIMATED_TIME SERVER_URL SNAPSHOT_NAME GETH_NAME <<< "${SNAPSHOTS[$i]}"

  # Display server header with Estim. Time
  echo -ne "Server $SERVER_NUMBER: $SNAPSHOT_TYPE | "
  echo -e "${RED}Estim. Time: $ESTIMATED_TIME${NC}"

  # Form a line of info, separated by '|'
  INFO_LINE="$SNAPSHOT_HEIGHT ($SNAPSHOT_AGE, $BLOCKS_BEHIND blocks ago) | Size: $TOTAL_SIZE_GB (${project} $SNAPSHOT_SIZE, Geth $GETH_SIZE)"

  # Display snapshot information in green
  printGreen "$INFO_LINE"

  # Display server URL in blue
  printBlue "$SERVER_URL"

  printLine
done

# Read user choice
echo -ne "${GREEN}Choose a server to install snapshot and press enter ${NC}"
echo -ne "(${SNAPSHOTS[*]//|*}): "
read -r CHOICE

# Check user choice and install the corresponding snapshot
VALID_CHOICE=false
for i in "${!SNAPSHOTS[@]}"; do
  IFS='|' read -r SERVER_NUMBER SNAPSHOT_TYPE SNAPSHOT_HEIGHT BLOCKS_BEHIND SNAPSHOT_AGE TOTAL_SIZE_GB SNAPSHOT_SIZE GETH_SIZE ESTIMATED_TIME SERVER_URL SNAPSHOT_NAME GETH_NAME <<< "${SNAPSHOTS[$i]}"
  if [[ "$CHOICE" == "$SERVER_NUMBER" ]]; then
    install_snapshot "$SNAPSHOT_NAME" "$GETH_NAME" "$SERVER_URL"
    VALID_CHOICE=true
    break
  fi
done

if ! $VALID_CHOICE; then
  printRed "Invalid choice. Exiting."
  exit 1
fi