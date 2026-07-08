#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh

docker buildx build --load --provenance=false --sbom=false -t "$APP_IMAGE" app/synthetic-api
