# ScaleOps Kubernetes Failure Lab Handoff

Date: 2026-07-06

## Current Project Status

This repository now contains a working local Kubernetes performance failure lab for ScaleOps TAM interview preparation. The lab uses a local kind cluster, a synthetic FastAPI workload, k6 load tests, Kustomize scenario overlays, optional Datadog observability, runbooks, and scenario reports.

The project has been pushed to GitHub:

```text
https://github.com/falliwillfollow/k8lab
```

Current branch:

```text
main
```

Latest pushed scenario-report commit:

```text
093065a Add underprovisioned scenario report
```

## Major Accomplishments

### Local Lab Scaffold

Created the requested repository structure, including:

- `app/synthetic-api/`
- `cluster/`
- `k8s/base/`
- `k8s/overlays/`
- `load/k6/`
- `observability/`
- `scripts/`
- `docs/`
- `runbooks/`

### Synthetic API

Built a FastAPI workload with endpoints for controlled failure and pressure testing:

- `GET /healthz`
- `GET /readyz`
- `GET /work`
- `GET /cpu`
- `GET /memory`
- `GET /leak`
- `GET /metrics`

The app includes safeguards for bounded CPU burn, memory allocation, and leak behavior.

### Kubernetes Baseline

Implemented:

- Namespace: `scaleops-lab`
- Deployment: `synthetic-api`
- Service: `synthetic-api`
- ConfigMap for synthetic app behavior
- Liveness and readiness probes
- Datadog-friendly labels and log annotation

Normal baseline resources:

```text
replicas: 2
cpu request: 100m
cpu limit: 500m
memory request: 128Mi
memory limit: 512Mi
```

### kind Cluster

Created a local kind architecture with:

```text
1 control-plane node
2 worker nodes
```

Current observed state before planned reboot:

```text
scaleops-lab-control-plane   Ready
scaleops-lab-worker          Ready
scaleops-lab-worker2         Ready
```

### Metrics Server

Installed metrics-server with kind-compatible kubelet TLS settings.

This enables:

```bash
kubectl top nodes
kubectl -n scaleops-lab top pods
```

and supports future HPA scenarios.

### Datadog Integration

Installed Datadog through Helm using `.env` configuration.

Important Datadog values added for kind compatibility:

```yaml
datadog:
  clusterName: scaleops-lab
  kubelet:
    tlsVerify: false

agents:
  containers:
    agent:
      env:
        - name: DD_HOSTNAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
```

This fixed:

- Agent hostname detection failure inside kind.
- Kubelet TLS verification errors in the local kind environment.

Current observed Datadog state before planned reboot:

```text
datadog-agent cluster-agent   Running
datadog-agent operator        Running
datadog-agent node agents     3/3 Running on both workers
```

### Makefile Workflow

Implemented the teaching-focused Makefile interface:

```bash
make help
make check
make cluster-up
make cluster-down
make build
make load-image
make install-metrics-server
make install-datadog
make deploy SCENARIO=normal
make status
make logs
make load-test TEST=baseline
make snapshot
make clean
```

Each command prints a short concept note before executing.

### Load Tests

Implemented k6 tests:

- `baseline.js`
- `cpu-spike.js`
- `memory-spike.js`
- `latency-spike.js`
- `ramp-cpu.js`

Current local load path uses `kubectl port-forward` to the Service.

Important caveat discovered:

```text
kubectl port-forward svc/synthetic-api can concentrate traffic on one backend pod.
```

This is acceptable for initial learning, but a cluster-native k6 Job should be added later for more realistic service load balancing.

### Scenario Overlays

Implemented Kustomize overlays for:

- `normal`
- `overprovisioned`
- `underprovisioned`
- `cpu-throttling`
- `memory-pressure`
- `bad-hpa-signal`
- `hpa-lag`
- `bad-probes`

### Runbooks

Created runbooks for:

- Baseline
- Overprovisioned
- Underprovisioned
- CPU throttling
- Memory pressure
- Bad HPA signal
- HPA lag
- Bad probes

Each runbook follows the requested scenario structure.

### Learning Docs

Created learner-facing docs:

- `docs/00-learning-path.md`
- `docs/01-core-kubernetes-concepts.md`
- `docs/02-resource-requests-and-limits.md`
- `docs/03-scheduler-and-pending-pods.md`
- `docs/04-autoscaling.md`
- `docs/05-probes.md`
- `docs/06-datadog-observability.md`
- `docs/07-interview-narrative.md`

## Completed Scenario Walkthroughs

### 1. Normal Baseline

Baseline was deployed and verified.

Observed:

- 2 healthy pods.
- No restarts.
- `/healthz`, `/readyz`, and `/work` returned successfully.
- k6 baseline passed with 0% errors.
- Baseline p95 latency was roughly `82-99ms`.

Snapshot captured:

```text
snapshots/20260705-125704
```

No full standalone report has been written for baseline yet.

### 2. Overprovisioned

The overprovisioned scenario was tuned to reliably demonstrate scheduling pressure on James' local kind workers.

Final overlay configuration:

```text
replicas: 4
cpu request: 10000m
cpu limit: 11000m
memory request: 768Mi
memory limit: 1Gi
```

Observed:

- 2 high-request pods Running.
- 2 high-request pods Pending.
- 1 old pod remained Running during the stuck rollout.
- Scheduler events showed `Insufficient cpu`.
- Datadog showed Pending pods and a request-vs-usage mismatch.

Key scheduler event:

```text
0/3 nodes are available:
1 node(s) had untolerated taint(s),
2 Insufficient cpu.
```

Full report written:

```text
docs/overprovisioned-scenario-report.md
```

Snapshots captured:

```text
snapshots/20260705-130753
snapshots/20260705-131149
```

### 3. Underprovisioned

The underprovisioned scenario was deployed after overprovisioned to show the opposite failure mode.

Configuration:

```text
replicas: 2
cpu request: 25m
cpu limit: 500m
memory request: 64Mi
memory limit: 256Mi
```

Observed:

- Pods scheduled easily.
- No Pending pods.
- No restarts.
- CPU usage exceeded the request under load.
- Datadog showed the hot pod reaching about `836m` CPU against a `25m` request.
- Datadog showed CPU throttling around `13:41-13:42`.
- k6 CPU spike completed with 0% errors, but p95 latency rose to about `1.27s`.

Important caveat:

```text
The local port-forward load path concentrated most traffic on one pod.
```

Full report written:

```text
docs/underprovisioned-scenario-report.md
```

Snapshot captured:

```text
snapshots/20260705-134241
```

## Current Runtime State Before Reboot

At the time this handoff was written, the cluster was still running and the active workload state was the `underprovisioned` scenario:

```text
synthetic-api-64dbf44fdc-glj5d   1/1 Running
synthetic-api-64dbf44fdc-n9hmv   1/1 Running
```

Datadog was also running:

```text
datadog-agent-cczhp                           3/3 Running
datadog-agent-cluster-agent-6f84bdfc6-mvdgh   1/1 Running
datadog-agent-operator-7cf4f85f4-bbpjw        1/1 Running
datadog-agent-wlfnm                           3/3 Running
```

## Restart / Resume Notes

After system reboot, Docker should start again, but kind node containers may not automatically return to a healthy state.

First check:

```bash
cd ~/Projects/k8
export PATH="$HOME/.local/bin:$PATH"
docker ps
kind get clusters
kubectl get nodes
```

If the existing kind cluster is still healthy:

```bash
kubectl get nodes
kubectl -n scaleops-lab get pods
kubectl -n datadog get pods
```

If nodes are missing, stopped, or unhealthy, use the clean rebuild path:

```bash
make cluster-down
make cluster-up
make load-image
make install-metrics-server
make deploy SCENARIO=normal
make install-datadog
```

If the Docker group is not active in a fresh shell:

```bash
newgrp docker
```

If direct commands like `kubectl` are not found:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Scenarios Still Left To Walk Through And Document

The remaining scenarios have overlays and runbooks, but do not yet have full scenario reports based on observed Datadog/kubectl evidence.

### 1. CPU Throttling

Path:

```text
k8s/overlays/cpu-throttling/
runbooks/cpu-throttling.md
```

Configuration:

```text
cpu request: 100m
cpu limit: 200m
memory request: 128Mi
memory limit: 512Mi
replicas: 2
```

Recommended load:

```bash
make deploy SCENARIO=cpu-throttling
make load-test TEST=cpu-spike
make snapshot
```

Expected evidence:

- CPU usage approaches the low `200m` limit.
- Datadog shows CPU throttling.
- k6 latency increases.
- Error rate may remain low.

Report still needed:

```text
docs/cpu-throttling-scenario-report.md
```

### 2. Memory Pressure / OOMKilled

Path:

```text
k8s/overlays/memory-pressure/
runbooks/memory-pressure.md
```

Configuration:

```text
memory limit: 256Mi
```

Recommended load:

```bash
make deploy SCENARIO=memory-pressure
make load-test TEST=memory-spike
make snapshot
```

Expected evidence:

- Memory usage rises toward limit.
- One or more pods may restart.
- `kubectl describe pod` may show `OOMKilled`.
- Datadog should show memory spike and restart event.

Report still needed:

```text
docs/memory-pressure-scenario-report.md
```

### 3. Bad HPA Signal

Path:

```text
k8s/overlays/bad-hpa-signal/
runbooks/bad-hpa-signal.md
```

Configuration:

```text
CPU-based HPA enabled
minReplicas: 2
maxReplicas: 8
target CPU utilization: 60%
```

Recommended load:

```bash
make install-metrics-server
make deploy SCENARIO=bad-hpa-signal
make load-test TEST=latency-spike
make snapshot
```

Expected evidence:

- Latency rises because requests sleep.
- CPU does not rise enough to drive useful scaling.
- HPA exists but does little or nothing.

Report still needed:

```text
docs/bad-hpa-signal-scenario-report.md
```

### 4. HPA Lag

Path:

```text
k8s/overlays/hpa-lag/
runbooks/hpa-lag.md
```

Configuration:

```text
CPU-based HPA enabled
READY_STARTUP_DELAY_SECONDS: 15
target CPU utilization: 50%
```

Recommended load:

```bash
make install-metrics-server
make deploy SCENARIO=hpa-lag
make load-test TEST=ramp-cpu
make snapshot
```

Expected evidence:

- CPU rises.
- HPA desired replicas increases.
- New pods are created.
- Readiness delay postpones useful capacity.
- Latency may spike before recovery.

Report still needed:

```text
docs/hpa-lag-scenario-report.md
```

### 5. Bad Probes

Path:

```text
k8s/overlays/bad-probes/
runbooks/bad-probes.md
```

Configuration:

```text
READY_FAIL_RATE: 0.35
livenessProbe points to /readyz
readinessProbe is aggressive
```

Recommended commands:

```bash
make deploy SCENARIO=bad-probes
kubectl -n scaleops-lab describe pod <pod-name>
kubectl -n scaleops-lab get endpoints synthetic-api -w
make snapshot
```

Expected evidence:

- Pods flap Ready/NotReady.
- Liveness failures may restart containers.
- Service endpoints change frequently.
- Datadog should show probe failures, restarts, and possible request symptoms.

Report still needed:

```text
docs/bad-probes-scenario-report.md
```

### 6. Baseline Report

Although baseline was run successfully, a formal report has not yet been written.

Useful future report:

```text
docs/baseline-scenario-report.md
```

Expected content:

- Healthy deployment configuration.
- k6 baseline result.
- Healthy Datadog signals.
- What "normal" looks like before failure testing.

## Recommended Next Work

1. Add cluster-native k6 Job support so load spreads more naturally through the Service.
2. Run and document `cpu-throttling`.
3. Run and document `memory-pressure`.
4. Run and document `bad-hpa-signal`.
5. Run and document `hpa-lag`.
6. Run and document `bad-probes`.
7. Add a concise index page linking all scenario reports.
8. Optionally add a rightsized remediation overlay and compare before/after telemetry.

## Git / Local Notes

Secrets and local outputs are intentionally ignored:

```text
.env
snapshots/
```

An untracked `.obsidian/` directory was present locally when this handoff was written. It was not committed.

Before stopping work, check:

```bash
git status --short
```

If a new report should be published:

```bash
git add docs/<report-name>.md
git commit -m "Add <scenario> scenario report"
git push
```

