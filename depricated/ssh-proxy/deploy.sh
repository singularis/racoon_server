#!/bin/bash
set -e


IMAGE_TAG="docker.io/singularis314/ssh-proxy:0.1"

echo "Building SSH Proxy Docker image..."
docker build -t $IMAGE_TAG .
echo "Pushing SSH Proxy Docker image..."
docker push $IMAGE_TAG
ansible-playbook ssh-proxy.yaml -e "image_name=$IMAGE_TAG"

echo "Restarting SSH Proxy deployment..."
kubectl rollout restart deployment/ssh-proxy -n ssh-proxy

