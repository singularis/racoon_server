kubectl delete deployments.apps -n samba samba-timemachine-deployment
kubectl delete pvc -n samba samba-timemachine-pvc
kubectl delete pv -n samba samba-timemachine-pv
kubectl delete -n samba cm samba-data-config
ansible-playbook  /home/dante/racoon_server/workload/samba/samba.yaml