# Baseline Scenario Report

## Executive Summary

The `normal` baseline scenario established the known-good behavior for the `synthetic-api` workload before introducing failure modes.

The baseline showed:

```text
2 healthy replicas
No restarts
Stable Service endpoints
Low request latency
0% request failures
Healthy liveness and readiness probes
No scheduling pressure
No OOMKills
No probe-induced restart loops
```

This report is intentionally shorter than the failure reports. Its purpose is to define what "normal" looked like so later scenarios can be compared against a stable control case.

Core takeaway:

> A baseline turns every later symptom into a comparison instead of a guess.

## Lab Environment

```text
Cluster name: scaleops-lab
Provider: kind
Topology:
  - 1 control-plane node
  - 2 worker nodes
Namespace: scaleops-lab
Workload: synthetic-api
Image: synthetic-api:local
Observability: Datadog Agent installed via Helm
Load generator: k6 through kubectl port-forward
```

APM was enabled later in the lab and confirmed separately. The initial baseline evidence was gathered before most failure scenarios were run.

## Scenario Configuration

Files:

```text
k8s/base/deployment.yaml
k8s/base/configmap.yaml
k8s/overlays/normal/
load/k6/baseline.js
```

Normal resource configuration:

```yaml
replicas: 2
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
```

Normal probe configuration:

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: http
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 2
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /readyz
    port: http
  initialDelaySeconds: 3
  periodSeconds: 5
  timeoutSeconds: 2
  failureThreshold: 3
```

Important probe meaning:

```text
/healthz answers whether the process is alive.
/readyz answers whether the pod should receive traffic.
```

This clean separation became important later in the `bad-probes` scenario.

## Deployment Command

The baseline scenario is deployed with:

```bash
make deploy SCENARIO=normal
```

Expected healthy pod state:

```text
synthetic-api   2 desired replicas
pod 1           1/1 Running
pod 2           1/1 Running
```

Expected Service state:

```text
synthetic-api Service has two ready backend endpoints
```

## Load Test Configuration

File:

```text
load/k6/baseline.js
```

Baseline load:

```javascript
export const options = {
  vus: 4,
  duration: '45s',
  thresholds: {
    http_req_failed: ['rate<0.02'],
    http_req_duration: ['p(95)<500'],
  },
};

export default function () {
  const res = http.get(`${BASE_URL}/work?cpu_ms=20&memory_mb=2&sleep_ms=20`);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(1);
}
```

Command:

```bash
make load-test TEST=baseline
```

The baseline request applies modest work:

```text
20ms CPU burn
2MB temporary memory allocation
20ms sleep
4 virtual users
45 seconds
```

## Observed Baseline Results

The baseline run completed successfully.

Observed:

```text
Pods: 2 healthy replicas
Restarts: 0
Request failures: 0%
Baseline p95 latency: roughly 82-99ms
```

After APM was enabled later in the lab, a baseline smoke test showed similar healthy behavior:

```text
APM-enabled baseline p95 latency: ~92ms
```

Interpretation:

```text
The application was serving normally.
The baseline workload stayed comfortably below the failure thresholds.
The cluster had enough schedulable capacity for the normal deployment.
The probes were correctly configured and stable.
```

## Healthy Kubernetes Signals

A healthy baseline should show:

```text
Deployment available replicas equals desired replicas.
Pods are 1/1 Running.
Restart counts stay at 0.
Service endpoints are populated.
Readiness stays stable.
Liveness does not restart containers.
No Pending pods.
No CrashLoopBackOff.
No OOMKilled last state.
```

This becomes the contrast for later scenarios:

```text
Overprovisioned: Pending pods and scheduler Insufficient cpu events.
Underprovisioned: usage far above request and latency increase.
CPU throttling: usage reaches limit and throttled time rises.
Memory pressure: restart with OOMKilled last state.
Bad HPA signal: latency rises while CPU is a weak signal.
HPA lag: HPA reacts, but new capacity arrives late.
Bad probes: liveness restarts healthy-enough containers and endpoints disappear.
```

## Healthy Datadog Signals

Useful Datadog baseline views:

```text
Pod status: Running
Restart metrics: flat at 0
CPU usage: modest relative to limit
Memory usage: modest relative to limit
Container CPU throttled: near zero or low
APM request latency: low and stable
APM request errors: near zero
Kubernetes events: no sustained warning pattern
```

The important part is not that every metric is perfectly flat. The important part is that no control-plane or runtime signal indicates instability.

## Why This Baseline Matters

The baseline is the control group for the lab.

Without it, later statements would be vague:

```text
Latency was high.
Pods were unhealthy.
CPU looked strange.
The HPA did not help enough.
```

With it, the lab can make stronger comparisons:

```text
Baseline p95 was roughly 82-99ms; CPU throttling raised p95 to about 1.6s.
Baseline had no restarts; memory pressure created an OOMKilled restart.
Baseline had stable endpoints; bad probes caused endpoints to go empty.
Baseline scheduled normally; overprovisioning left pods Pending.
```

## Diagnosis

The baseline diagnosis is:

```text
The workload is healthy under normal configuration and modest load.
```

That means later failures are caused by deliberate scenario changes, not by a broken application, broken cluster, or broken load generator.

## Remediation

No remediation is needed for the baseline.

Use it as the reset target after experiments:

```bash
make deploy SCENARIO=normal
```

If an HPA object from an autoscaling scenario is still present and should be removed:

```bash
kubectl -n scaleops-lab delete hpa synthetic-api
```

## Interview Narrative

If explaining this scenario in an interview:

> Before testing failure modes, I established a healthy baseline. The normal deployment used two replicas with realistic requests and limits, separate liveness and readiness probes, stable Service endpoints, no restarts, and low p95 latency around 82-99ms. That gave me a control case. When later scenarios showed Pending pods, throttling, OOMKilled restarts, HPA lag, or probe-induced CrashLoopBackOff, I could compare each symptom against known-good behavior instead of treating the metrics in isolation.

## Artifacts

Snapshot captured:

```text
snapshots/20260705-125704
```
