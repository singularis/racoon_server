#!/bin/bash

# Set the KUBECONFIG environment variable
export KUBECONFIG=/home/dante/.kube/config

# Remove Kafka and Zookeeper directories
sudo rm -rf /other/kafka/kafka-1/*
sudo rm -rf /other/zookeeper/zookeeper-1/*

# Force delete the pods
kubectl -n kafka-new delete pod kafka-kafka-0 --grace-period=0 --force
kubectl -n kafka-new delete pod kafka-zookeeper-0 --grace-period=0 --force

# Rollout restart the deployments
kubectl rollout restart deployment kafka-entity-operator -n kafka-new
kubectl rollout restart deployment strimzi-cluster-operator -n kafka-new
