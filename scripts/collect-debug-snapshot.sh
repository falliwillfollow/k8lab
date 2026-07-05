#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh

timestamp="$(date +%Y%m%d-%H%M%S)"
dir="snapshots/$timestamp"
mkdir -p "$dir"

run() {
  local name="$1"
  shift
  echo "+ $*" > "$dir/$name.txt"
  "$@" >> "$dir/$name.txt" 2>&1 || true
}

run nodes-wide kubectl get nodes -o wide
run describe-nodes kubectl describe nodes
run namespace-all kubectl -n "$NAMESPACE" get all -o wide
run describe-deployments kubectl -n "$NAMESPACE" describe deployments
run describe-pods kubectl -n "$NAMESPACE" describe pods
run events kubectl -n "$NAMESPACE" get events --sort-by=.lastTimestamp
run top-pods kubectl -n "$NAMESPACE" top pods
run top-nodes kubectl top nodes
run logs kubectl -n "$NAMESPACE" logs deploy/synthetic-api --tail=200
run hpa kubectl -n "$NAMESPACE" get hpa -o yaml

echo "Snapshot written to $dir"

