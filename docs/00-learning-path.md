# Learning Path

1. Run `make cluster-up` and inspect `kubectl get nodes`.
2. Deploy `normal` and learn what healthy pods, deployments, and services look like.
3. Read [01-core-kubernetes-concepts.md](docs/01-core-kubernetes-concepts.md).
4. Read [02-resource-requests-and-limits.md](docs/02-resource-requests-and-limits.md).
5. Deploy `overprovisioned` and look for Pending pods or wasted requested capacity.
6. Deploy `underprovisioned` and run CPU and memory load.
7. Deploy `cpu-throttling` and watch latency rise under CPU pressure.
8. Deploy `memory-pressure` and trigger restart/OOM evidence.
9. Install metrics-server, then deploy HPA scenarios.
10. Deploy `bad-hpa-signal` and prove CPU autoscaling is not a universal latency fix.
11. Deploy `hpa-lag` and observe reactive scaling delay.
12. Deploy `bad-probes` and practice explaining liveness vs readiness.
13. Read [07-interview-narrative.md](docs/07-interview-narrative.md) and rehearse the slow-site troubleshooting answer.

