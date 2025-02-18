#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Set the KUBECONFIG environment variable
export KUBECONFIG=/home/dante/.kube/config

echo "KUBECONFIG set to $KUBECONFIG"

# Check if KUBECONFIG file exists
if [ ! -f "$KUBECONFIG" ]; then
    echo "Error: KUBECONFIG file not found at $KUBECONFIG"
    exit 1
fi

# Force delete the pods
echo "Deleting Kafka and Zookeeper pods..."
kubectl -n kafka-new delete pod kafka-kafka-0 --grace-period=0 --force || true
kubectl -n kafka-new delete pod kafka-zookeeper-0 --grace-period=0 --force || true
kubectl -n kafka-new delete pod kafka-kafka-1 --grace-period=0 --force || true
kubectl -n kafka-new delete pod kafka-zookeeper-1 --grace-period=0 --force || true

# Rollout restart the deployments
echo "Restarting Kafka Entity Operator deployment..."
kubectl rollout restart deployment kafka-entity-operator -n kafka-new

echo "Restarting Strimzi Cluster Operator deployment..."
kubectl rollout restart deployment strimzi-cluster-operator -n kafka-new

echo "Rollouts initiated successfully."

echo
