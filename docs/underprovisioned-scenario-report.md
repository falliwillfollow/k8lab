# Underprovisioned Workload Scenario Report

## Executive Summary

The `underprovisioned` scenario intentionally configured the `synthetic-api` Deployment with resource requests that were much lower than the workload's actual CPU needs under load.

The pods scheduled easily because Kubernetes only reserved `25m` CPU per pod. During the CPU spike test, one pod used hundreds of millicores of CPU, approached or exceeded its `500m` CPU limit, showed CPU throttling in Datadog, and produced much higher request latency.

This demonstrates a core Kubernetes resource-sizing concept:

> Low requests can make a workload look cheap to the scheduler while hiding the real resources needed for reliable performance.

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

## Scenario Configuration

File:

```text
k8s/overlays/underprovisioned/patch-resources.yaml
```

Configuration:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: synthetic-api
  namespace: scaleops-lab
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: synthetic-api
          resources:
            requests:
              cpu: "25m"
              memory: "64Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
```

Effective resource configuration:

```text
Replicas: 2
CPU request per pod: 25m
CPU limit per pod: 500m
Memory request per pod: 64Mi
Memory limit per pod: 256Mi
```

The CPU request is deliberately tiny. The CPU limit is still present, which lets the scenario show both under-requesting and CPU limit pressure.

## Deployment Command

The scenario was deployed with:

```bash
make deploy SCENARIO=underprovisioned
```

The rollout completed successfully:

```text
deployment "synthetic-api" successfully rolled out
```

Observed pod state:

```text
synthetic-api-64dbf44fdc-glj5d   1/1   Running   scaleops-lab-worker
synthetic-api-64dbf44fdc-n9hmv   1/1   Running   scaleops-lab-worker2
```

This is an important contrast with the overprovisioned scenario. Underprovisioned pods are easy to schedule because the scheduler sees small requests.

## Load Test Configuration

File:

```text
load/k6/cpu-spike.js
```

Load test:

```javascript
export const options = {
  vus: 12,
  duration: '90s',
};

export default function () {
  const res = http.get(`${BASE_URL}/work?cpu_ms=300&memory_mb=1&sleep_ms=0`);
  check(res, { 'request completed': (r) => r.status < 500 });
  sleep(0.2);
}
```

Command:

```bash
make load-test TEST=cpu-spike
```

The synthetic API endpoint burned approximately `300ms` of CPU per request.

## k6 Results

The CPU spike completed successfully, but latency increased sharply.

```text
Requests: 1026
Error rate: 0.00%
Average latency: 860.95ms
p90 latency: 1.14s
p95 latency: 1.27s
Max latency: 1.84s
```

Baseline comparison:

```text
Healthy baseline p95: ~82-99ms
Underprovisioned CPU spike p95: ~1.27s
```

Interpretation:

```text
The application did not fail outright.
It became much slower under CPU pressure.
```

That matters operationally because CPU/resource problems often appear as latency before they appear as errors.

## Kubernetes Symptoms

The pods stayed healthy from a Kubernetes lifecycle perspective:

```text
READY: 1/1
STATUS: Running
RESTARTS: 0
```

There were no Pending pods in this scenario after the underprovisioned rollout completed. That is expected.

The key `kubectl top pods` observation during load was:

```text
synthetic-api-64dbf44fdc-glj5d   484m-487m CPU
synthetic-api-64dbf44fdc-n9hmv   ~2m CPU
```

Resource request:

```text
25m CPU
```

Observed hot-pod usage:

```text
~487m CPU
```

Ratio:

```text
487m / 25m = ~19.5x requested CPU
```

Your Datadog screenshot showed an even higher max for the hot pod:

```text
synthetic-api-64dbf44fdc-glj5d max CPU: ~836m
```

Ratio using that Datadog value:

```text
836m / 25m = ~33x requested CPU
```

## Datadog Symptoms

Datadog showed three useful signals.

### 1. CPU Usage Above Request

The `synthetic-api-64dbf44fdc-glj5d` pod spiked far above its configured request.

```text
CPU request: 25m
Observed max CPU in Datadog: ~836m
```

This is the core underprovisioning evidence: the scheduler was told the pod needed only `25m`, but the workload used much more under realistic pressure.

### 2. CPU Throttling

The Datadog query:

```text
avg:container.cpu.throttled{*} by {pod_name}
```

showed a throttling spike around:

```text
13:41-13:42
```

The graph peaked around hundreds of milliseconds of throttled CPU time.

Interpretation:

```text
The container wanted more CPU than the runtime allowed under the configured CPU limit.
```

This is sharper than simply saying "CPU was high." It means the container was being delayed by CPU enforcement.

### 3. Latency Increase

The app logs and k6 output showed `/work` latency around:

```text
~800ms-1200ms during the CPU spike
```

Example app log shape:

```json
{"pod":"synthetic-api-64dbf44fdc-glj5d","path":"/work","status":200,"latency_ms":1005.5}
```

The important correlation is:

```text
CPU spike + CPU throttling + higher request latency occurred in the same time window.
```

## Load Distribution Caveat

The load test used local `kubectl port-forward` against the Kubernetes Service:

```bash
kubectl -n scaleops-lab port-forward svc/synthetic-api 8080:80
```

In this run, traffic concentrated mostly on one backend pod:

```text
Hot pod: synthetic-api-64dbf44fdc-glj5d
Idle pod: synthetic-api-64dbf44fdc-n9hmv
```

This is a local load-generation artifact. It is still useful because it created a clear CPU-pressure symptom, but a more realistic cluster-native load test should run k6 inside the cluster so Service load balancing is exercised more naturally.

Potential future improvement:

```text
Add a make load-test-cluster TEST=cpu-spike target that runs k6 as a Kubernetes Job.
```

## Diagnosis

The workload was underprovisioned because the CPU request understated the amount of CPU the application needed under load.

The failure mode was not:

- Scheduling failure.
- Image pull failure.
- Pod crash.
- Readiness failure.
- Liveness failure.
- Memory OOM.

The failure mode was:

```text
Performance degradation caused by CPU demand far exceeding the CPU request, plus CPU limit pressure and throttling.
```

In plain language:

```text
The pod was cheap to schedule but expensive to run.
```

## Remediation Strategy

A good remediation should avoid simply guessing a larger number. Use telemetry and validate the outcome.

### 1. Right-size CPU Requests

Raise CPU requests to reflect observed sustained and percentile usage.

Example:

```text
Current request: 25m
Observed hot-pod max: ~836m
Potential starting request for this test profile: 250m-500m
```

The exact request should depend on normal traffic, p95/p99 usage, latency goals, and how much headroom the service needs.

### 2. Revisit CPU Limits

The `500m` CPU limit created a hard ceiling. If organizational policy allows it, consider raising or removing CPU limits for latency-sensitive services.

Options:

```text
Conservative: request 250m, limit 1000m
More burst-friendly: request 500m, no CPU limit
Policy-bound: request 500m, limit 1000m
```

The tradeoff:

```text
Higher/no CPU limit can reduce throttling but may allow noisy-neighbor behavior if node capacity is not managed well.
```

### 3. Add Replicas If The Workload Scales Horizontally

If traffic is evenly balanced and the app is stateless, more replicas can reduce per-pod CPU pressure.

However, replicas only help if traffic actually spreads across pods. Because this run used `kubectl port-forward`, load concentrated on one pod. Validate with cluster-native load before drawing final scaling conclusions.

### 4. Consider HPA If CPU Is A Good Signal

This scenario is a reasonable candidate for CPU-based HPA because the bottleneck is CPU-bound work.

Potential policy:

```text
minReplicas: 2
maxReplicas: 8
target CPU utilization: 60%
```

But HPA requires realistic requests. If the request is too low, utilization percentages can be misleading and scaling behavior can become too sensitive.

### 5. Validate With Before/After Telemetry

After changing requests, limits, or replicas, rerun the same load test and compare:

```text
p95 latency
CPU usage
CPU throttling
error rate
pod restarts
node pressure
cost/requested capacity
```

The goal is not just "more resources." The goal is lower latency and less throttling without wasting excessive schedulable capacity.

## Recommended Experiment Follow-up

Try a rightsized overlay later with:

```text
replicas: 2
requests:
  cpu: "250m"
  memory: "128Mi"
limits:
  cpu: "1000m"
  memory: "512Mi"
```

Then rerun:

```bash
make deploy SCENARIO=normal
make load-test TEST=cpu-spike
```

Compare against this underprovisioned result:

```text
Underprovisioned p95: ~1.27s
Underprovisioned throttling: visible spike
```

## Commands Used For Diagnosis

```bash
kubectl -n scaleops-lab get pods -o wide
kubectl -n scaleops-lab top pods
kubectl -n scaleops-lab get deploy synthetic-api -o yaml
kubectl -n scaleops-lab logs deploy/synthetic-api --tail=20
kubectl -n scaleops-lab get events --sort-by=.lastTimestamp
make load-test TEST=cpu-spike
make snapshot
```

Snapshot captured:

```text
snapshots/20260705-134241
```

## Interview Narrative

A concise explanation:

> I deployed an underprovisioned version of the API with a CPU request of only 25 millicores and a CPU limit of 500 millicores. The pods scheduled easily, which is expected because the scheduler only had to reserve a tiny amount of CPU. But under CPU load, Datadog showed the hot pod using hundreds of millicores, roughly 20x to 33x its request, and CPU throttling spiked around the same time k6 latency rose to about 1.27 seconds p95. This shows that low requests can improve bin packing on paper while creating performance risk at runtime.

Short version:

> The workload was schedulable, but the request was not truthful.

## Key Lesson

Underprovisioning is not mainly a scheduling failure. It is a reliability and performance risk.

Low requests can make capacity planning look efficient, but if actual usage is consistently or predictably higher, the workload may suffer from latency, throttling, noisy-neighbor effects, and misleading autoscaling behavior.

