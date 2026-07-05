#!/usr/bin/env bash
set -euo pipefail

kubectl apply -k cluster
kubectl -n kube-system rollout status deploy/metrics-server --timeout=120s
echo "Try: kubectl top nodes && kubectl -n scaleops-lab top pods"

