#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh

docker build -t "$APP_IMAGE" app/synthetic-api

