# ScaleOps Kubernetes Failure Lab

This project is a local Kubernetes learning lab designed for debugging and resource-optimization practice. It deploys a small synthetic API to a local kind cluster, then intentionally creates common Kubernetes failure modes: overprovisioning, underprovisioning, CPU throttling, memory pressure, bad autoscaling signals, autoscaling lag, and probe misconfiguration.

The goal is not just to run Kubernetes. The goal is to learn how Kubernetes symptoms appear in `kubectl`, cluster events, workload metrics, and Datadog, then practice explaining remediation tradeoffs clearly.

## Quick Start

```bash
cp .env.example .env
make check
make cluster-up
make build
make load-image
make install-metrics-server
make deploy SCENARIO=normal
make load-test TEST=baseline
make snapshot
```

Optional Datadog:

```bash
# Put DD_API_KEY and DD_SITE in .env first.
make install-datadog
```

## Common Commands

```bash
make deploy SCENARIO=overprovisioned
make deploy SCENARIO=underprovisioned
make deploy SCENARIO=cpu-throttling
make deploy SCENARIO=memory-pressure
make deploy SCENARIO=bad-hpa-signal
make deploy SCENARIO=hpa-lag
make deploy SCENARIO=bad-probes
make status
make logs
make cluster-down
```

If direct commands like `kubectl get pods` are not found, refresh your shell path:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Local API

After deploying, `make load-test` automatically port-forwards the service. To inspect manually:

```bash
kubectl -n scaleops-lab port-forward svc/synthetic-api 8080:80
curl http://127.0.0.1:8080/healthz
curl "http://127.0.0.1:8080/work?cpu_ms=200&memory_mb=20&sleep_ms=100"
curl http://127.0.0.1:8080/metrics
```

## Learning Path

Start with [docs/00-learning-path.md](docs/00-learning-path.md), then use the runbooks in [runbooks](runbooks).
