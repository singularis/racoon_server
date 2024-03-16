#! /bin/bash

docker build -t singularis314/ubuntu_dev:0.1 .
docker push singularis314/ubuntu_dev:0.1
kubectl rollout restart -n development deploy ubuntu-dev-deployment
