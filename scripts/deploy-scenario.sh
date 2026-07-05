#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh

scenario="${1:-normal}"
overlay="k8s/overlays/$scenario"

if [[ ! -d "$overlay" ]]; then
  echo "Unknown scenario: $scenario"
  echo "Available scenarios:"
  find k8s/overlays -mindepth 1 -maxdepth 1 -type d -printf '  %f\n' | sort
  exit 1
fi

kubectl apply -k "$overlay"
kubectl -n "$NAMESPACE" rollout status deploy/synthetic-api --timeout=180s || true
kubectl -n "$NAMESPACE" get pods -o wide
kubectl -n "$NAMESPACE" get hpa 2>/dev/null || true

