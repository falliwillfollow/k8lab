#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh

if kind get clusters | grep -qx "$CLUSTER_NAME"; then
  echo "Cluster $CLUSTER_NAME already exists."
else
  kind create cluster --config cluster/kind-config.yaml --name "$CLUSTER_NAME"
fi

kubectl cluster-info --context "kind-$CLUSTER_NAME"
kubectl get nodes -o wide

