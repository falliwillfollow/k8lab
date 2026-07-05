#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh

scripts/build-image.sh
if kind get clusters | grep -qx "$CLUSTER_NAME"; then
  scripts/load-image.sh
else
  echo "Cluster $CLUSTER_NAME does not exist yet; image built locally only."
fi
