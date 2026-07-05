#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh

test_name="${1:-baseline}"
script="load/k6/$test_name.js"

if [[ ! -f "$script" ]]; then
  echo "Unknown load test: $test_name"
  find load/k6 -maxdepth 1 -name '*.js' -printf '  %f\n' | sort
  exit 1
fi

cleanup() {
  if [[ -n "${PF_PID:-}" ]]; then
    kill "$PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

kubectl -n "$NAMESPACE" port-forward svc/synthetic-api 8080:80 >/tmp/scaleops-lab-port-forward.log 2>&1 &
PF_PID=$!
sleep 3

if command -v k6 >/dev/null 2>&1; then
  BASE_URL="${BASE_URL:-http://127.0.0.1:8080}" k6 run "$script"
else
  echo "k6 binary not found; using Docker image grafana/k6."
  docker run --rm --network host -e BASE_URL="${BASE_URL:-http://127.0.0.1:8080}" \
    -v "$PWD/load/k6:/scripts:ro" grafana/k6 run "/scripts/$test_name.js"
fi

