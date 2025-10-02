#!/usr/bin/env bash
set -euo pipefail

# Cordon and drain racoon-gpu before shutdown/reboot.
# Steps:
# 1) Cordon node
# 2) Evict pods (graceful)
# 3) After 60s, force delete remaining non-excluded pods
# 4) Wait additional 60s and exit (allow shutdown to continue)

GPU_NODE="racoon-gpu"

log() { printf "[%s] %s\n" "$(date +"%Y-%m-%dT%H:%M:%S")" "$*"; }

exclude() {
  local ns=$1 name=$2
  case "$ns" in
    kube-system|kafka-new|minio|nextcloud|pihole|neo4j|samba|monitoring|openwebui|pgadmin|gphoto|calico-system|tigera-operator|lens-metrics)
      return 0 ;;
  esac
  [[ "$name" =~ ^(kube-apiserver|kube-controller-manager|kube-scheduler|etcd)- ]] && return 0 || true
  return 1
}

cordon_node() {
  if kubectl get node "$GPU_NODE" >/dev/null 2>&1; then
    log "Cordoning $GPU_NODE"
    kubectl cordon "$GPU_NODE" || true
  fi
}

list_pods_on_gpu() {
  kubectl get pods -A -o json | jq -r --arg node "$GPU_NODE" '
    .items[] | select(.spec.nodeName == $node) |
    select((.metadata.ownerReferences // []) | all(.kind != "DaemonSet")) |
    select(.metadata.deletionTimestamp | not) |
    [.metadata.namespace, .metadata.name] | @tsv
  '
}

graceful_evict() {
  mapfile -t pods < <(list_pods_on_gpu)
  for line in "${pods[@]}"; do
    ns=${line%%$'\t'*}
    name=${line#*$'\t'}
    if exclude "$ns" "$name"; then
      log "Skip excluded: $ns/$name"
      continue
    fi
    log "Evicting $ns/$name"
    kubectl -n "$ns" evict pod/"$name" --grace-period=30 --timeout=40s >/dev/null 2>&1 || true
  done
}

force_delete_leftovers() {
  mapfile -t pods < <(list_pods_on_gpu)
  for line in "${pods[@]}"; do
    ns=${line%%$'\t'*}
    name=${line#*$'\t'}
    if exclude "$ns" "$name"; then
      continue
    fi
    log "Force deleting leftover $ns/$name"
    kubectl -n "$ns" delete pod "$name" --grace-period=0 --force --timeout=15s >/dev/null 2>&1 || true
  done
}

main() {
  if ! kubectl version >/dev/null 2>&1; then
    log "kubectl not available; skipping drain"
    exit 0
  fi
  cordon_node
  graceful_evict
  log "Waiting 60s for graceful evictions"
  sleep 60
  force_delete_leftovers
  log "Waiting 60s to settle"
  sleep 60
  log "GPU shutdown drain finished"
}

main "$@"


