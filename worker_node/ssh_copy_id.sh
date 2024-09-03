#!/bin/bash

VARS_FILE="../vars.yaml"

# Function to extract worker node IP and username from vars.yaml
extract_worker_ip() {
  awk '/worker_node:/{flag=1;next}/^[^ ]/{flag=0}flag' "$VARS_FILE" | grep 'ip:' | awk '{print $2}' | tr -d '\"'
}

extract_worker_user() {
  awk '/worker_node:/{flag=1;next}/^[^ ]/{flag=0}flag' "$VARS_FILE" | grep 'user:' | awk '{print $2}' | tr -d '\"'
}

# Extract the worker node IP and username
WORKER_IP=$(extract_worker_ip)
WORKER_USER=$(extract_worker_user)

if [[ -z "$WORKER_IP" ]] || [[ -z "$WORKER_USER" ]]; then
  echo "Worker node IP or username not found in vars.yaml. Exiting."
  exit 1
fi

# Copy SSH key to the worker node
echo "Copying SSH key to $WORKER_USER@$WORKER_IP..."
ssh-copy-id -i ~/.ssh/id_rsa.pub "$WORKER_USER@$WORKER_IP"