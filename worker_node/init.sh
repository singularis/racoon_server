#!/bin/bash

VARS_FILE="../vars.yaml"

# Function to extract worker node IP from vars.yaml
extract_worker_ip() {
  awk '/worker_node:/{flag=1;next}/^[^ ]/{flag=0}flag' "$VARS_FILE" | grep 'ip:' | awk '{print $2}' | tr -d '\"'
}

# Function to extract worker node username from vars.yaml
extract_worker_user() {
  awk '/worker_node:/{flag=1;next}/^[^ ]/{flag=0}flag' "$VARS_FILE" | grep 'user:' | awk '{print $2}' | tr -d '\"'
}

# Extract the worker node IP and username
WORKER_IP=$(extract_worker_ip)
WORKER_USER=$(extract_worker_user)

echo IP $WORKER_IP  user $WORKER_IP

# Check if IP or username are empty
if [[ -z "$WORKER_IP" ]] || [[ -z "$WORKER_USER" ]]; then
  echo "Worker node IP or username not found in vars.yaml. Exiting."
  exit 1
fi

INIT_SCRIPT="./initial_installation.sh"

echo "Copying initial installation script to worker node..."
scp "$INIT_SCRIPT" "$WORKER_USER@$WORKER_IP:~/$INIT_SCRIPT"

echo "Running initial installation on worker node..."
ssh "$WORKER_USER@$WORKER_IP" "sudo bash ~/initial_installation.sh"

echo "Initial installation completed on worker node."
