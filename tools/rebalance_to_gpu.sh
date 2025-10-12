#!/usr/bin/env bash
set -euo pipefail

# Fast pod rebalancing toward racoon-gpu node.
# Logic:
# 1) Uncordon gpu node
# 2) Cordon worker and racoon to prevent new assignments
# 3) Evict pods on other nodes except exclusions
# 4) Uncordon worker
# 5) Uncordon racoon
# Requirements: kubectl available on racoon-gpu and node has permissions.

GPU_NODE="racoon-gpu"
RACOON_NODE="racoon"

# Optional: specify worker node via environment; leave empty to skip worker actions
WORKER_NODE="${WORKER_NODE:-}"

# Ensure kubectl has access to cluster when run non-interactively
if [[ -z "${KUBECONFIG:-}" && -f /etc/kubernetes/admin.conf ]]; then
  export KUBECONFIG=/etc/kubernetes/admin.conf
fi

# Ensure PATH includes sbin locations when launched by systemd
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

# Wait configuration (can be overridden via environment)
WAIT_TIMEOUT_SEC="${WAIT_TIMEOUT_SEC:-300}"
WAIT_INTERVAL_SEC="${WAIT_INTERVAL_SEC:-5}"

# Static exclusions: do not evict stateful/local PV backed services
# Namespaces and names derived from repository manifests
declare -a EXCLUDE_PATTERNS=(
  "^kafka-new/"                # Strimzi Kafka (brokers/controllers/state)
  "^minio/"                    # MinIO namespace from values
  "^pihole/"                   # Pi-hole
  "^jenkins/"                  # Jenkins
  "^nextcloud/"                # Nextcloud + nextcloud-db (Zalando Postgres)
  "^neo4j/"                    # Neo4j
  "^samba/"                    # Samba timemachine
  "^gphoto/"                   # Google Photos PVs
  "^openwebui/"                # OpenWebUI PVs
  "^monitoring/"               # Grafana/Elastic PVs
  "^pgadmin/"                  # PGAdmin PV
  "^kube-system/"              # Kubernetes system namespaces
  "^calico-system/"            # CNI system namespace
  "^tigera-operator/"          # Calico operator
  "^lens-metrics/"             # Lens metrics
)

log() { printf "[%s] %s\n" "$(date +"%Y-%m-%dT%H:%M:%S")" "$*"; }

wait_for_kube_api() {
  local deadline=$((SECONDS + WAIT_TIMEOUT_SEC))
  while (( SECONDS < deadline )); do
    if kubectl version --request-timeout=5s >/dev/null 2>&1; then
      return 0
    fi
    log "Waiting for Kubernetes API..."
    sleep "$WAIT_INTERVAL_SEC"
  done
  log "Timed out waiting for Kubernetes API after ${WAIT_TIMEOUT_SEC}s"
  return 1
}

wait_for_node_registration() {
  local node=$1
  local deadline=$((SECONDS + WAIT_TIMEOUT_SEC))
  while (( SECONDS < deadline )); do
    if kubectl get node "$node" -o name --request-timeout=5s >/dev/null 2>&1; then
      return 0
    fi
    log "Waiting for node $node to register..."
    sleep "$WAIT_INTERVAL_SEC"
  done
  log "Timed out waiting for node $node registration after ${WAIT_TIMEOUT_SEC}s"
  return 1
}

wait_for_node_ready() {
  local node=$1
  local deadline=$((SECONDS + WAIT_TIMEOUT_SEC))
  while (( SECONDS < deadline )); do
    if node_ready "$node"; then
      return 0
    fi
    log "Waiting for node $node to become Ready..."
    sleep "$WAIT_INTERVAL_SEC"
  done
  log "Timed out waiting for node $node to be Ready after ${WAIT_TIMEOUT_SEC}s"
  return 1
}

node_ready() {
  local node=$1
  kubectl get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q True || return 1
}

uncordon_if_needed() {
  local node=$1
  if kubectl get node "$node" -o jsonpath='{.spec.unschedulable}' 2>/dev/null | grep -q true; then
    log "Uncordoning node: $node"
    kubectl uncordon "$node" || true
  else
    log "Node already schedulable: $node"
  fi
}

cordon_if_needed() {
  local node=$1
  if kubectl get node "$node" -o jsonpath='{.spec.unschedulable}' 2>/dev/null | grep -q true; then
    log "Node already cordoned: $node"
  else
    log "Cordoning node: $node"
    kubectl cordon "$node" || true
  fi
}

should_exclude() {
  local ns=$1 name=$2
  local key="$ns/$name"
  for pat in "${EXCLUDE_PATTERNS[@]}"; do
    if [[ "$key" =~ $pat ]]; then
      return 0
    fi
  done
  return 1
}

evict_pod() {
  local ns=$1 name=$2
  if kubectl -n "$ns" get pod "$name" >/dev/null 2>&1; then
    log "Evicting $ns/$name"
    if ! kubectl -n "$ns" evict pod/"$name" --grace-period=10 --timeout=30s 2>/dev/null; then
      # Try a regular delete with a short grace period
      if ! kubectl -n "$ns" delete pod "$name" --grace-period=10 --timeout=30s >/dev/null 2>&1; then
        # Last resort: force delete with zero grace to break stuck pods
        kubectl -n "$ns" delete pod "$name" --grace-period=0 --force --timeout=15s >/dev/null 2>&1 || true
      fi
    fi
  fi
}

fast_label_gpu_preference() {
  kubectl label node "$GPU_NODE" racoon/prefer-gpu=true --overwrite >/dev/null 2>&1 || true
}

main() {
  # Ensure Kubernetes API is reachable and the GPU node is Ready
  wait_for_kube_api || exit 1
  wait_for_node_registration "$GPU_NODE" || exit 1
  wait_for_node_ready "$GPU_NODE" || exit 1

  # Step 1: uncordon gpu node first
  uncordon_if_needed "$GPU_NODE"

  fast_label_gpu_preference

  # Step 2: cordon worker and racoon to prevent new assignments
  if [[ -n "${WORKER_NODE}" ]] && kubectl get node "$WORKER_NODE" >/dev/null 2>&1; then
    cordon_if_needed "$WORKER_NODE"
  fi
  if kubectl get node "$RACOON_NODE" >/dev/null 2>&1; then
    cordon_if_needed "$RACOON_NODE"
  fi

  # Collect pods from non-GPU nodes excluding DaemonSets and mirror/static pods
  mapfile -t pods < <(kubectl get pods -A -o json | jq -r \
    --arg gpu "$GPU_NODE" '
      .items[]
      | select(.spec.nodeName and .spec.nodeName != $gpu)
      | select((.metadata.ownerReferences // []) | all(.kind != "DaemonSet"))
      | select(.metadata.deletionTimestamp | not)
      | [.metadata.namespace, .metadata.name] | @tsv
    ')

  # Step 3: Evict pods except exclusions
  for line in "${pods[@]}"; do
    ns=${line%%$'\t'*}
    name=${line#*$'\t'}
    if should_exclude "$ns" "$name"; then
      log "Skip excluded: $ns/$name"
      continue
    fi
    evict_pod "$ns" "$name" &
  done

  wait || true

  # Step 4: uncordon worker (if specified)
  if [[ -n "${WORKER_NODE}" ]] && kubectl get node "$WORKER_NODE" >/dev/null 2>&1; then
    uncordon_if_needed "$WORKER_NODE"
  fi

  # Step 5: uncordon racoon
  if kubectl get node "$RACOON_NODE" >/dev/null 2>&1; then
    uncordon_if_needed "$RACOON_NODE"
  fi

  log "Rebalancing complete"
}

main "$@"


