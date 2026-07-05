#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh

kind delete cluster --name "$CLUSTER_NAME"

