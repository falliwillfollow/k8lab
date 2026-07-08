# Memory Pressure Scenario Report

## Executive Summary

The `memory-pressure` scenario intentionally configured the `synthetic-api` Deployment with a low memory limit of `256Mi` per pod.

Under memory-heavy load, one backend pod received most of the traffic, exceeded its memory limit, was killed by the container runtime, and restarted. Kubernetes later showed the pod as Running again, but `kubectl describe pod` preserved the previous container termination reason as `OOMKilled` with exit code `137`.

This demonstrates a core Kubernetes resource-sizing concept:

> CPU pressure can slow a container down; memory limit pressure can terminate it.

In this run, the clearest evidence came from Kubernetes `lastState`, Datadog restart metrics, a Datadog `last_state.terminated` metric tagged with `reason:oomkilled`, and a containerd out-of-memory event.

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
k8s/overlays/memory-pressure/patch-resources.yaml
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
              cpu: "500m"
              memory: "256Mi"
```

Effective resource configuration:

```text
Replicas: 2
CPU request per pod: 100m
CPU limit per pod: 500m
Memory request per pod: 128Mi
Memory limit per pod: 256Mi
```

Because this memory limit is set in the Deployment pod template, every replica created by the Deployment receives the same `256Mi` memory limit. The uneven behavior in this run came from uneven load distribution, not different pod configuration.

## Deployment Command

The scenario was deployed with:

```bash
make deploy SCENARIO=memory-pressure
```

The rollout completed successfully:

```text
deployment "synthetic-api" successfully rolled out
```

Observed pod state after rollout:

```text
synthetic-api-6496d77b8b-b6jsd   1/1   Running   scaleops-lab-worker2
synthetic-api-6496d77b8b-crp7z   1/1   Running   scaleops-lab-worker
```

Both pods had the same configured resources:

```text
requests={"cpu":"100m","memory":"128Mi"}
limits={"cpu":"500m","memory":"256Mi"}
```

## Load Test Configuration

File:

```text
load/k6/memory-spike.js
```

Load test:

```javascript
export const options = {
  vus: 6,
  duration: '60s',
};

export default function () {
  const res = http.get(`${BASE_URL}/memory?mb=120&hold_seconds=4`, { timeout: '20s' });
  check(res, { 'request completed': (r) => r.status < 500 });
  sleep(0.5);
}
```

Command:

```bash
make load-test TEST=memory-spike
```

The synthetic API endpoint allocated approximately `120MB` per request and held it for `4` seconds. With overlapping requests on one backend pod, this can exceed the `256Mi` container memory limit.

## k6 Results

The memory spike caused request failures after the backend connected through port-forward was killed.

The k6 output showed repeated request errors:

```text
EOF
dial tcp 127.0.0.1:8080: connect: connection refused
```

The final k6 summary showed:

```text
Requests: 708
HTTP request failed: 100.00%
```

Important caveat:

```text
checks_succeeded showed 100%, but http_req_failed showed 100% failures.
```

The check in `memory-spike.js` is too loose:

```javascript
check(res, { 'request completed': (r) => r.status < 500 });
```

Failed network requests can have status `0`, which still satisfies `status < 500`. For this run, `http_req_failed` is the correct k6 signal to trust.

## Kubernetes Symptoms

After the load test, one pod had restarted:

```text
synthetic-api-6496d77b8b-b6jsd   1/1   Running   1 restart
synthetic-api-6496d77b8b-crp7z   1/1   Running   0 restarts
```

The hot pod was back in Running state, but `kubectl describe pod` showed the previous container termination:

```text
Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
  Started:      Tue, 07 Jul 2026 19:31:39 -0400
  Finished:     Tue, 07 Jul 2026 19:32:16 -0400
Restart Count:  1
Limits:
  memory:  256Mi
Requests:
  memory:  128Mi
```

Interpretation:

```text
The pod recovered because Kubernetes restarted the container.
The previous container instance was killed for exceeding its memory limit.
```

This is an important operational detail. A quick `kubectl get pods` can show the pod as healthy after recovery, while `kubectl describe pod` reveals the previous OOM kill.

## Datadog Symptoms

Datadog showed the scenario through multiple signals.

### 1. Containerd Out-Of-Memory Event

Datadog captured a container runtime event:

```text
Task b970fb57e2ae739d69c9b0d7cac267f3e9ff049d5ba6b0563b1d286e18775ada ran out of memory
```

This is direct runtime evidence that the container exceeded available memory.

### 2. Container Restart Metric

The container restart metric increased to `1` for the affected pod.

Useful query:

```text
avg:kubernetes.containers.restarts{pod_name:synthetic-api-6496d77b8b-b6jsd}
```

Interpretation:

```text
The container was killed and then started again by Kubernetes.
```

### 3. Last Terminated State Metric

The useful Datadog query was:

```text
avg:kubernetes.containers.last_state.terminated{pod_name:synthetic-api-6496d77b8b-b6jsd} by {reason}
```

Observed result:

```text
reason:oomkilled = 1
```

Interpretation:

```text
The container is currently Running, but its previous state was Terminated for reason OOMKilled.
```

This matched Kubernetes `lastState.terminated.reason=OOMKilled`.

### 4. Current Terminated State Did Not Populate

The metric:

```text
kubernetes.containers.state.terminated
```

did not show the OOM as clearly.

This is expected for a fast restart. The container's current state quickly returned to Running, so current-state terminated metrics can miss the brief terminated window. The more reliable Datadog signal was:

```text
kubernetes.containers.last_state.terminated by {reason}
```

## Load Distribution Caveat

The load test used local `kubectl port-forward` against the Kubernetes Service:

```bash
kubectl -n scaleops-lab port-forward svc/synthetic-api 8080:80
```

In this run, traffic concentrated mostly on one backend pod:

```text
Hot pod: synthetic-api-6496d77b8b-b6jsd
Idle pod: synthetic-api-6496d77b8b-crp7z
```

This is a local load-generation artifact. It is still useful because it created a clear OOM symptom on one pod, but it is not ideal for demonstrating balanced Service behavior.

A better future experiment would run k6 inside the cluster as a Kubernetes Job so traffic goes through normal in-cluster Service routing.

## Diagnosis

The workload exceeded the configured memory limit on the hot pod.

The failure mode was not:

- Scheduling failure.
- Node memory exhaustion.
- CPU throttling.
- Image pull failure.
- Readiness probe failure.
- Liveness probe failure.

The failure mode was:

```text
Container termination caused by memory usage exceeding the container memory limit.
```

In plain language:

```text
The pod was healthy until the process used more memory than it was allowed to use.
Kubernetes restarted it after the runtime killed the container.
```

## Remediation Strategy

A good remediation should consider both resource sizing and application behavior.

### 1. Right-size Memory Requests And Limits

The current memory limit was too close to the memory pressure created by overlapping requests.

Options:

```text
Conservative: request 256Mi, limit 512Mi
More headroom: request 512Mi, limit 1Gi
Policy-dependent: request based on p95 memory, limit based on safe peak memory
```

The request should reflect normal expected memory usage. The limit should allow realistic peaks without permitting uncontrolled growth.

### 2. Investigate Memory Spikes And Leaks

For a real application, do not only raise the limit. Determine whether the spike is expected.

Questions to ask:

```text
Was this a legitimate peak?
Was memory released after the request?
Is there a leak?
Is concurrency bounded?
Can large allocations be streamed or chunked?
```

### 3. Add Application-Level Guardrails

The app can defend itself before Kubernetes has to kill it.

Examples:

```text
Reject oversized requests.
Limit concurrent memory-heavy work.
Use queues or backpressure.
Stream data instead of loading it all into memory.
```

### 4. Validate With Before/After Telemetry

After changing memory requests, limits, or application behavior, rerun the same load test and compare:

```text
memory usage
memory limit
restart count
OOMKilled events
request failures
latency
node memory pressure
per-pod traffic distribution
```

The goal is not simply "more memory." The goal is to avoid OOM kills while still preserving sensible capacity boundaries.

## Recommended Experiment Follow-up

Try a less restrictive memory limit:

```text
replicas: 2
requests:
  cpu: "100m"
  memory: "256Mi"
limits:
  cpu: "500m"
  memory: "512Mi"
```

Then rerun:

```bash
make deploy SCENARIO=normal
make load-test TEST=memory-spike
```

Compare against this memory-pressure result:

```text
Memory pressure restart count: 1
Memory pressure last termination reason: OOMKilled
Memory pressure http_req_failed: 100%
```

## Commands Used For Diagnosis

```bash
make deploy SCENARIO=memory-pressure
kubectl -n scaleops-lab get pods -o wide
kubectl -n scaleops-lab get deploy synthetic-api -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{" requests="}{.resources.requests}{" limits="}{.resources.limits}{"\n"}{end}'
kubectl -n scaleops-lab top pods
kubectl -n scaleops-lab describe pod synthetic-api-6496d77b8b-b6jsd
kubectl -n scaleops-lab logs synthetic-api-6496d77b8b-b6jsd --previous --tail=80
kubectl -n scaleops-lab get events --sort-by=.lastTimestamp
make load-test TEST=memory-spike
make snapshot
```

Snapshot captured:

```text
snapshots/20260707-193322
```

## Interview Narrative

A concise explanation:

> I deployed a memory-pressure version of the API with a memory limit of 256Mi per pod. During a memory-heavy load test, one backend pod received most of the traffic and exceeded that limit. The container runtime emitted an out-of-memory event, Kubernetes restarted the container, and `kubectl describe pod` showed `Last State: Terminated`, `Reason: OOMKilled`, and exit code 137. Datadog also showed the restart count increasing to 1 and `kubernetes.containers.last_state.terminated` tagged with `reason:oomkilled`. This shows the difference between CPU pressure and memory pressure: CPU pressure may slow a container down, but exceeding a memory limit kills and restarts it.

Short version:

> The pod looked healthy after recovery, but its last container instance died from OOMKilled.

## Key Lesson

Memory pressure often leaves evidence after the workload has recovered.

Do not stop at `kubectl get pods`. Check restart count, `kubectl describe pod`, previous logs, runtime events, and Datadog last-state metrics. A pod can be Running now while still carrying the evidence of an OOM kill in its previous container state.
