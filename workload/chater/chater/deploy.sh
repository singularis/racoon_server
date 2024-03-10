#! /bin/bash

docker build -t singularis314/chater:0.3 .
docker push singularis314/chater:0.3
kubectl rollout restart -n chater deployment chater-deployment