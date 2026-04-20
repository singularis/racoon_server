#!/bin/bash
set -e

# Default to the hostname of the current machine if no node name is provided
NODE_NAME="${1:-$(hostname)}"

echo "Initiating graceful shutdown for Kubernetes node: $NODE_NAME"

# Ensure we have the correct kubeconfig
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

# Verify kubectl access and node existence
if ! kubectl get node "$NODE_NAME" >/dev/null 2>&1; then
    echo "Error: Cannot find node '$NODE_NAME' or kubectl is not configured correctly."
    exit 1
fi

echo "Step 1: Cordoning node to prevent new pods from scheduling..."
kubectl cordon "$NODE_NAME"

echo "Step 2: Draining workloads from node to reschedule on healthy instances..."
kubectl drain "$NODE_NAME" \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --force \
    --grace-period=60 \
    --timeout=300s

echo "Drain completed successfully. Node is safe to shut down or reboot."
