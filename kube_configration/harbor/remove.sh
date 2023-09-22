#!/bin/bash
helm uninstall -n harbor harbor
kubectl delete pvc --all -n harbor
kubectl delete pv --all -n harbor