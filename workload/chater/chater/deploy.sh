#! /bin/bash

docker build -t singularis314/chater:0.2 .
docker push singularis314/chater:0.2
kubectl rollout restart -n chater deployment chater-deployment