#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh

if [[ -z "${DD_API_KEY:-}" || "${DD_API_KEY}" == "replace_me" ]]; then
  echo "DD_API_KEY is not configured. Put it in .env, then rerun make install-datadog."
  exit 1
fi

kubectl create namespace datadog --dry-run=client -o yaml | kubectl apply -f -
kubectl -n datadog create secret generic datadog-secret \
  --from-literal api-key="$DD_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

helm repo add datadog https://helm.datadoghq.com
helm repo update datadog
helm upgrade --install datadog-agent datadog/datadog \
  --namespace datadog \
  --values observability/datadog-values.yaml \
  --set datadog.site="$DD_SITE" \
  --set datadog.apiKeyExistingSecret=datadog-secret

echo "Validation:"
echo "  kubectl -n datadog get pods"
echo "  kubectl -n datadog logs daemonset/datadog-agent -c agent --tail=50"

