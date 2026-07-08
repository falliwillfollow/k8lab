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

APM has also been enabled for the synthetic API:

```text
observability/datadog-values.yaml enables APM on port 8126.
app/synthetic-api uses ddtrace and starts with ddtrace-run.
k8s/base/deployment.yaml sets DD_AGENT_HOST, DD_TRACE_AGENT_PORT, DD_ENV, DD_SERVICE, and DD_VERSION.
```

After changing APM instrumentation, rebuild and reload the app image:

```bash
make build
make load-image
kubectl -n scaleops-lab rollout restart deploy/synthetic-api
```

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

Full report written:

```text
docs/baseline-scenario-report.md
```

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

### 4. CPU Throttling

The cpu-throttling scenario was deployed to show latency from a low CPU limit.

Configuration:

```text
replicas: 2
cpu request: 100m
cpu limit: 200m
memory request: 128Mi
memory limit: 512Mi
```

Observed:

- Both pods rolled out successfully.
- One pod received most of the port-forward load.
- The hot pod reached the `200m` CPU limit.
- Datadog showed CPU throttled time on the hot pod, with max throttled time around `939ms`.
- Node CPU remained low, confirming this was container-level limit pressure rather than node exhaustion.
- k6 CPU spike completed with 0% errors, but p95 latency rose to about `1.6s`.

Important caveat:

```text
The local port-forward load path concentrated most traffic on one pod, so Datadog evidence was clearest when filtered by pod_name.
```

Full report written:

```text
docs/cpu-throttling-scenario-report.md
```

Snapshot captured:

```text
snapshots/20260707-191529
```

### 5. Memory Pressure

The memory-pressure scenario was deployed to show container termination from exceeding a memory limit.

Configuration:

```text
replicas: 2
cpu request: 100m
cpu limit: 500m
memory request: 128Mi
memory limit: 256Mi
```

Observed:

- Both pods rolled out successfully.
- One pod received most of the port-forward load.
- The hot pod restarted once.
- `kubectl describe pod` showed `Last State: Terminated`, `Reason: OOMKilled`, and `Exit Code: 137`.
- containerd emitted an event: `Task ... ran out of memory`.
- Datadog showed the container restart metric increase to `1`.
- Datadog showed `kubernetes.containers.last_state.terminated` grouped by `reason`, with `reason:oomkilled = 1`.
- `kubernetes.containers.state.terminated` did not populate usefully because the container returned to Running quickly.

Important caveats:

```text
The local port-forward load path concentrated most traffic on one pod.
The k6 check was too loose: http_req_failed showed 100% failures even though checks_succeeded showed 100%.
```

Full report written:

```text
docs/memory-pressure-scenario-report.md
```

Snapshot captured:

```text
snapshots/20260707-193322
```

### 6. Bad HPA Signal

The bad-hpa-signal scenario was deployed to show a CPU-based HPA watching a weak signal for a latency-heavy workload.

Configuration:

```text
replicas: 2
cpu request: 100m
cpu limit: 500m
memory request: 128Mi
memory limit: 512Mi
HPA minReplicas: 2
HPA maxReplicas: 8
HPA CPU target: 60%
```

Load:

```text
/work?cpu_ms=5&memory_mb=1&sleep_ms=900
```

Observed:

- APM showed request latency rising to about `0.9s`.
- k6 p95 latency was about `920-923ms`.
- Error rate stayed at 0%.
- Pods stayed Running with no restarts.
- The HPA was healthy and reading CPU metrics.
- Initial HPA samples showed `37%/60%`, then `62%/60%` and `64%/60%`, while desired replicas stayed at `2`.
- After APM was enabled and the latency spike was rerun, the HPA eventually moved to `3` replicas because incidental CPU crossed the target.

Important interpretation:

```text
The HPA was not broken. It was watching CPU, which was only a weak indirect proxy for the real symptom: request latency from waiting.
```

Full report written:

```text
docs/bad-hpa-signal-scenario-report.md
```

Snapshot captured before APM enablement:

```text
snapshots/20260707-200839
```

### 7. HPA Lag

The hpa-lag scenario was deployed to show that HPA can react correctly but still arrive too late to prevent latency.

Configuration:

```text
replicas: 2
cpu request: 100m
cpu limit: 800m
memory request: 128Mi
memory limit: 512Mi
READY_STARTUP_DELAY_SECONDS: 15
HPA minReplicas: 2
HPA maxReplicas: 8
HPA CPU target: 50%
```

Load:

```text
/work?cpu_ms=250&memory_mb=1&sleep_ms=0
```

Observed:

- HPA started at `2%/50%` with 2 replicas.
- Under ramping CPU load, HPA saw `203%/50%`, then `293%/50%`, then `392%/50%`.
- HPA scaled from `2` to `4`, then to max replicas `8`.
- New pods existed as `0/1 Running` during the readiness delay before becoming useful capacity.
- Kubernetes events showed readiness probe `503` failures, expected from the intentional startup delay.
- k6 completed with 0% failures, but p95 latency rose to about `1.34s`.
- APM showed latency rising during the scale-up window and dropping when load ramped down.
- HPA overshot to max replicas because demand remained high while new pods were still warming.

Important caveat:

```text
The local port-forward load path again concentrated most traffic on one pod, so extra replicas did not help as much as they would with cluster-native load.
```

Full report written:

```text
docs/hpa-lag-scenario-report.md
```

Snapshot captured:

```text
snapshots/20260707-204515
```

### 8. Bad Probes

The bad-probes scenario was deployed to show how incorrect health-check semantics can destabilize otherwise runnable containers.

Configuration:

```text
READY_FAIL_RATE: 0.35
livenessProbe path: /readyz
readinessProbe path: /readyz
liveness periodSeconds: 3
liveness failureThreshold: 1
readiness periodSeconds: 3
readiness failureThreshold: 1
```

Observed:

- Both pods entered `CrashLoopBackOff`.
- Restart counts increased quickly.
- Kubernetes events showed readiness and liveness probe failures.
- Events showed `Container synthetic-api failed liveness probe, will be restarted`.
- Service endpoints went empty while pods were unready or restarting.
- EndpointSlice still had pod IPs, but `ready: false` and `serving: false`.
- Baseline k6 load failed with `180/180` failed requests and `http_req_failed = 100%`.
- Datadog should show unhealthy pods, restarts, probe events, and possible APM gaps or request failures.

Important caveat:

```text
An HPA object from the previous HPA scenario was still present because apply-based overlay deployment does not prune resources. It showed cpu: <unknown>/50% because pods were unready, but it was not the cause of this failure.
```

Full report written:

```text
docs/bad-probes-scenario-report.md
```

Snapshot captured:

```text
snapshots/20260707-210503
```

## Current Runtime State

As of the latest 2026-07-07 resume session, Datadog APM is enabled and the active workload state is the `bad-probes` scenario:

```text
synthetic-api-685f465896-27rb2   0/1   CrashLoopBackOff   7 restarts
synthetic-api-685f465896-bpnhw   0/1   CrashLoopBackOff   4 restarts
synthetic-api-685f465896-xgdsh   0/1   CrashLoopBackOff   7 restarts
```

The Service had no ready endpoints during the last sample:

```text
endpoints/synthetic-api   <empty>
```

The workload was intentionally left in this broken state so Datadog evidence could be inspected before resetting to `normal`.

Reset command:

```bash
make deploy SCENARIO=normal
```

An HPA object from the previous HPA scenario is still present because the current apply-based workflow does not prune resources that disappear from a later overlay:

```text
synthetic-api   Deployment/synthetic-api   cpu: <unknown>/50%   min 2   max 8   replicas 3
```

This stale HPA is not the cause of the `bad-probes` failure.

APM verification from the resume session:

```text
Datadog Agent APM receiver: 0.0.0.0:8126
Python tracer client: ddtrace 2.20.0
Observed previous-minute intake: 1058 traces, 2116 spans
APM-enabled latency-spike p95: ~923ms
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

All planned scenario walkthroughs now have standalone reports:

```text
docs/baseline-scenario-report.md
docs/overprovisioned-scenario-report.md
docs/underprovisioned-scenario-report.md
docs/cpu-throttling-scenario-report.md
docs/memory-pressure-scenario-report.md
docs/bad-hpa-signal-scenario-report.md
docs/hpa-lag-scenario-report.md
docs/bad-probes-scenario-report.md
```

## Recommended Next Work

1. Add cluster-native k6 Job support so load spreads more naturally through the Service.
2. Add a concise index page linking all scenario reports.
3. Optionally add a rightsized remediation overlay and compare before/after telemetry.

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
