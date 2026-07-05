#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

CLUSTER_NAME="${CLUSTER_NAME:-scaleops-lab}"
NAMESPACE="${NAMESPACE:-scaleops-lab}"
APP_IMAGE="${APP_IMAGE:-synthetic-api:local}"
DD_SITE="${DD_SITE:-datadoghq.com}"
