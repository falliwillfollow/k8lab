#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh

kind load docker-image "$APP_IMAGE" --name "$CLUSTER_NAME"

