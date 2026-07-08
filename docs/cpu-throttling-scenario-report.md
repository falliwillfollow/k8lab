# CPU Throttling Scenario Report

## Executive Summary

The `cpu-throttling` scenario intentionally configured the `synthetic-api` Deployment with a low CPU limit of `200m` per pod.

Under CPU-heavy load, one backend pod received most of the traffic, reached its CPU limit, showed CPU throttling in Datadog, and produced much higher request latency. The pod did not crash, restart, or become unhealthy, and the worker node still had spare CPU.

This demonstrates a common Kubernetes performance failure mode:

> CPU limits can create latency even when pods are Running and the node is not CPU saturated.

In this run, the most useful evidence came from looking at the hot pod directly instead of averaging across all replicas.

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
k8s/overlays/cpu-throttling/patch-resources.yaml
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
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "200m"
              memory: "512Mi"
```

Effective resource configuration:

```text
Replicas: 2
CPU request per pod: 100m
CPU limit per pod: 200m
Memory request per pod: 128Mi
Memory limit per pod: 512Mi
```

Because this limit is set in the Deployment pod template, every replica created by the Deployment receives the same `200m` CPU limit. The uneven behavior in this run came from uneven load distribution, not different pod configuration.

## Deployment Command

The scenario was deployed with:

```bash
make deploy SCENARIO=cpu-throttling
```

The rollout completed successfully:

```text
deployment "synthetic-api" successfully rolled out
```

Observed pod state:

```text
synthetic-api-f5ccb59c6-sxhkh   1/1   Running   scaleops-lab-worker2
synthetic-api-f5ccb59c6-xbxdk   1/1   Running   scaleops-lab-worker
```

Both pods had the same configured resources:

```text
requests={"cpu":"100m","memory":"128Mi"}
limits={"cpu":"200m","memory":"512Mi"}
```

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

The CPU spike completed without request failures, but latency increased sharply.

```text
Requests: 787
Error rate: 0.00%
Average latency: 1.17s
p90 latency: 1.49s
p95 latency: 1.6s
Max latency: 2.71s
```

Baseline comparison:

```text
Healthy baseline p95: ~72ms in the resume smoke test
CPU throttling p95: ~1.6s
```

Interpretation:

```text
The application remained available.
The application became much slower under CPU limit pressure.
```

This is the important operational pattern: CPU throttling can show up as latency before it shows up as errors, restarts, or obvious Kubernetes events.

## Kubernetes Symptoms

The pods stayed healthy from a Kubernetes lifecycle perspective:

```text
READY: 1/1
STATUS: Running
RESTARTS: 0
```

There were no Pending pods and no OOM kills. The scenario was not a scheduling failure or a memory failure.

The key `kubectl top pods` observation during load was:

```text
synthetic-api-f5ccb59c6-sxhkh   200m CPU   51Mi
synthetic-api-f5ccb59c6-xbxdk   2m CPU     37Mi
```

Resource limit:

```text
CPU limit: 200m per pod
```

Observed hot-pod usage:

```text
200m CPU
```

Interpretation:

```text
One pod was pinned at its CPU limit.
The other pod was mostly idle.
```

Node-level CPU was not saturated:

```text
scaleops-lab-worker2   250m CPU   1%
```

That distinction matters. The problem was not that the node was out of CPU. The hot container was constrained by its own CPU limit.

## Datadog Symptoms

Datadog showed the scenario most clearly when filtered to the hot pod:

```text
pod_name:synthetic-api-f5ccb59c6-sxhkh
```

Useful queries:

```text
avg:container.cpu.usage{namespace:scaleops-lab,kube_deployment:synthetic-api} by {pod_name}
avg:container.cpu.limit{namespace:scaleops-lab,kube_deployment:synthetic-api} by {pod_name}
avg:container.cpu.throttled{namespace:scaleops-lab,kube_deployment:synthetic-api} by {pod_name}
```

Observed Datadog evidence for the hot pod:

```text
CPU limit: flat at 200m
CPU usage max: ~216m
CPU throttled max: ~939ms
CPU throttled sum: ~4.81s
```

Interpretation:

```text
The pod wanted more CPU than the configured limit allowed.
The container runtime throttled it.
Latency increased while errors remained at 0%.
```

The all-pod graph was less clear because it averaged the hot pod together with the idle pod. When grouped or filtered by `pod_name`, the signal was much easier to explain.

## Why Usage Can Look Below Limit While Throttling Exists

CPU usage and CPU throttling are related, but they are not the same measurement.

CPU usage is an averaged rate over the metric rollup window. CPU limits are enforced in much shorter scheduling periods. A container can briefly hit its quota, get throttled, and then show an average usage value that appears below the limit after Datadog rollup and smoothing.

Also, `container.cpu.throttled` is a time-based metric. It is not another CPU usage line. It represents time the container was denied runnable CPU because of quota enforcement.

For this scenario, the correct read is:

```text
Usage near the 200m limit + throttled time spike + high latency + idle node = CPU limit pressure.
```

## Load Distribution Caveat

The load test used local `kubectl port-forward` against the Kubernetes Service:

```bash
kubectl -n scaleops-lab port-forward svc/synthetic-api 8080:80
```

In this run, traffic concentrated mostly on one backend pod:

```text
Hot pod: synthetic-api-f5ccb59c6-sxhkh
Idle pod: synthetic-api-f5ccb59c6-xbxdk
```

This is a local load-generation artifact. It is still useful because it created a clear CPU-throttling symptom on one pod, but it is not ideal for demonstrating balanced Service behavior.

A better future experiment would run k6 inside the cluster as a Kubernetes Job so traffic goes through normal in-cluster Service routing.

Potential future improvement:

```text
Add a make load-test-cluster TEST=cpu-spike target that runs k6 as a Kubernetes Job.
```

## Diagnosis

The workload experienced CPU throttling because the active pod's CPU demand exceeded its configured CPU limit.

The failure mode was not:

- Scheduling failure.
- Node CPU exhaustion.
- Image pull failure.
- Pod crash.
- Readiness failure.
- Liveness failure.
- Memory OOM.

The failure mode was:

```text
Performance degradation caused by CPU quota enforcement at the container level.
```

In plain language:

```text
The cluster had CPU available, but the container was not allowed to use more than 200m.
```

## Remediation Strategy

A good remediation should start by confirming that throttling is the actual bottleneck, then validating changes with the same load profile.

### 1. Raise Or Remove CPU Limits

For latency-sensitive services, a very low CPU limit can create avoidable throttling.

Options:

```text
Conservative: request 100m, limit 500m
More burst-friendly: request 200m, limit 1000m
Policy-dependent: request 200m, no CPU limit
```

The tradeoff:

```text
Higher or absent CPU limits reduce throttling risk but require stronger node capacity management.
```

### 2. Right-size CPU Requests

The request should represent the CPU the workload normally needs, not the burst ceiling.

In this scenario:

```text
Current request: 100m
Current limit: 200m
Observed hot-pod usage: near 200m during load
```

A reasonable next experiment would raise the request and limit together, then compare latency and throttling.

### 3. Add Replicas If Traffic Spreads

If the application is stateless and traffic balances normally, additional replicas can reduce per-pod CPU pressure.

However, this specific run concentrated traffic on one pod because of local port-forward behavior. More replicas would only help if the load path actually distributes requests.

### 4. Validate With Before/After Telemetry

After changing limits, requests, or replica count, rerun the same load test and compare:

```text
p95 latency
CPU usage
CPU throttling
error rate
pod restarts
node CPU saturation
per-pod traffic distribution
```

The goal is not just higher resource numbers. The goal is lower latency and less throttling without wasting excessive schedulable capacity.

## Recommended Experiment Follow-up

Try a less restrictive CPU limit:

```text
replicas: 2
requests:
  cpu: "200m"
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

Compare against this CPU throttling result:

```text
CPU throttling p95: ~1.6s
CPU throttling max throttled time on hot pod: ~939ms
```

## Commands Used For Diagnosis

```bash
make deploy SCENARIO=cpu-throttling
kubectl -n scaleops-lab get pods -o wide
kubectl -n scaleops-lab get deploy synthetic-api -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{" requests="}{.resources.requests}{" limits="}{.resources.limits}{"\n"}{end}'
kubectl -n scaleops-lab top pods
kubectl top nodes
kubectl -n scaleops-lab get events --sort-by=.lastTimestamp
make load-test TEST=cpu-spike
make snapshot
```

Snapshot captured:

```text
snapshots/20260707-191529
```

## Interview Narrative

A concise explanation:

> I deployed a CPU-throttling version of the API with a CPU limit of 200 millicores per pod. During CPU-heavy load, one backend pod received most of the traffic because of the local port-forward load path. That pod reached its 200 millicore CPU limit, Datadog showed a throttled-time spike near the same window, and k6 p95 latency rose to about 1.6 seconds with 0 percent request failures. Node CPU was still low, so this was not node exhaustion. It was container-level CPU quota enforcement causing latency.

Short version:

> The pod was Running, the node had spare CPU, but the container was capped.

## Key Lesson

CPU throttling is a performance failure mode, not necessarily an availability failure mode.

Pods can be healthy, replicas can be available, and nodes can have spare CPU while a container is still slowed by its own CPU limit. For diagnosis, correlate per-pod CPU usage, CPU throttled time, request latency, and node-level CPU before changing resources.
