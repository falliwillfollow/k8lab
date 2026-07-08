# Bad HPA Signal Scenario Report

## Executive Summary

The `bad-hpa-signal` scenario configured a CPU-based Horizontal Pod Autoscaler for the `synthetic-api` Deployment, then generated latency using request sleep time rather than CPU-heavy work.

The workload became slower from the user's perspective, with p95 request latency around `920ms`. CPU utilization did not strongly represent the bottleneck. The HPA initially stayed at `2` replicas and later, during an APM-enabled rerun, moved to `3` replicas only after incidental CPU usage crossed the target.

This demonstrates a core autoscaling concept:

> An HPA can be mechanically healthy while watching a signal that only weakly matches the user-facing symptom.

The key lesson is not that CPU stayed at zero. The key lesson is that the latency was caused primarily by waiting, while CPU was only an indirect side effect of request volume.

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
APM: enabled with ddtrace for FastAPI
Load generator: k6 through kubectl port-forward
```

## Scenario Configuration

Files:

```text
k8s/overlays/bad-hpa-signal/patch-resources.yaml
k8s/overlays/bad-hpa-signal/hpa.yaml
```

Deployment resource configuration:

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
              memory: "512Mi"
```

HPA configuration:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: synthetic-api
  namespace: scaleops-lab
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: synthetic-api
  minReplicas: 2
  maxReplicas: 8
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
```

Effective autoscaling policy:

```text
Minimum replicas: 2
Maximum replicas: 8
Scaling signal: average CPU utilization
Target CPU utilization: 60%
CPU request per pod: 100m
Approximate target CPU per pod: 60m
```

HPA CPU utilization is based on CPU request, not CPU limit. With a `100m` request and a `60%` target, the HPA tries to keep average pod CPU around `60m`.

## Deployment Command

The scenario was deployed with:

```bash
make install-metrics-server
make deploy SCENARIO=bad-hpa-signal
```

The rollout completed successfully and the HPA was created:

```text
deployment "synthetic-api" successfully rolled out
horizontalpodautoscaler.autoscaling/synthetic-api created
```

After metrics-server caught up, the HPA was healthy:

```text
ScalingActive: True
Reason: ValidMetricFound
```

Initial HPA state:

```text
synthetic-api   Deployment/synthetic-api   cpu: 2%/60%   min 2   max 8   replicas 2
```

## Load Test Configuration

File:

```text
load/k6/latency-spike.js
```

Load test:

```javascript
export const options = {
  vus: 20,
  duration: '90s',
};

export default function () {
  const res = http.get(`${BASE_URL}/work?cpu_ms=5&memory_mb=1&sleep_ms=900`, { timeout: '10s' });
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(0.1);
}
```

The endpoint did a tiny amount of CPU work, a tiny memory allocation, and then slept for about `900ms`.

In plain language:

```text
The request was slow because it waited, not because it burned CPU.
```

## k6 Results

The first run, before APM instrumentation was enabled, showed:

```text
Requests: 1792
Error rate: 0.00%
Average latency: 909.5ms
p90 latency: 912.81ms
p95 latency: 920.41ms
Max latency: 1.11s
```

After enabling APM, the latency spike was rerun and showed a similar result:

```text
Requests: 1789
Error rate: 0.00%
Average latency: 910.99ms
p90 latency: 914.56ms
p95 latency: 923.06ms
Max latency: 1.15s
```

Baseline comparison:

```text
Healthy baseline p95 after APM enablement: ~92ms
Bad HPA signal p95: ~923ms
```

Interpretation:

```text
The application stayed available.
The application became predictably slower because each request waited about 900ms.
```

## Kubernetes Symptoms

The pods stayed healthy from a Kubernetes lifecycle perspective:

```text
READY: 1/1
STATUS: Running
RESTARTS: 0
```

There were no Pending pods, OOM kills, or probe failures.

During the initial scenario run, HPA samples showed:

```text
cpu: 37%/60%   replicas: 2
cpu: 62%/60%   replicas: 2
cpu: 64%/60%   replicas: 2
```

The snapshot captured:

```text
current CPU: 62% / target 60%
current replicas: 2
desired replicas: 2
```

The hot-pod CPU sample was:

```text
synthetic-api-6c49b9d498-c9cgx   126m CPU
synthetic-api-6c49b9d498-gwh6j   2m CPU
```

This showed the familiar local port-forward artifact: most traffic concentrated on one backend pod.

## Why HPA Eventually Scaled To 3

After APM was enabled, the latency spike was rerun. During that later run, the HPA eventually moved the Deployment to `3` replicas:

```text
synthetic-api   Deployment/synthetic-api   cpu: 47%/60%   replicas 3
```

This does not invalidate the scenario. It clarifies it.

The request was mostly sleep-based:

```text
cpu_ms=5
sleep_ms=900
```

However, every request still used a small amount of CPU. With enough request volume, those small CPU slices accumulated. Because each pod requested only `100m`, the HPA target was approximately `60m` per pod. During the run, incidental CPU usage briefly crossed the target:

```text
62% / 60%
64% / 60%
```

The HPA formula is approximately:

```text
desired replicas = current replicas * current utilization / target utilization
```

At `2` replicas and `64%` CPU:

```text
2 * 64 / 60 = 2.13
```

HPA can round that up to `3` replicas.

The important diagnosis is:

```text
The HPA scaled because incidental CPU crossed the threshold, not because CPU was the real bottleneck.
```

That is why this remains a bad-signal scenario. The user-facing symptom was latency from waiting. CPU was only a weak indirect signal.

## Datadog Symptoms

APM was enabled before the second latency-spike run. Datadog Agent status confirmed trace intake:

```text
APM receiver: 0.0.0.0:8126
Python tracer client: ddtrace 2.20.0
Observed previous-minute intake: 1058 traces, 2116 spans
```

Datadog APM showed the latency spike for service:

```text
synthetic-api
```

Useful APM metric:

```text
avg:trace.fastapi.request{*}
```

Observed APM pattern:

```text
Request latency rose to roughly 0.9 seconds during the latency-spike run.
```

This was the missing application-level signal. Kubernetes metrics showed CPU, pod health, and HPA behavior; APM showed the user-facing request latency.

## Load Distribution Caveat

The load test used local `kubectl port-forward` against the Kubernetes Service:

```bash
kubectl -n scaleops-lab port-forward svc/synthetic-api 8080:80
```

In this run, traffic again concentrated mostly on one backend pod.

This matters for HPA interpretation:

```text
One pod did most of the work.
The average CPU signal could be distorted by one hot pod and one mostly idle pod.
```

A better future experiment would run k6 inside the cluster as a Kubernetes Job so traffic goes through normal in-cluster Service routing.

## Diagnosis

The HPA was configured correctly as a CPU-based HPA, and it was able to read CPU metrics.

The problem was the signal choice:

```text
The application symptom was request latency from waiting.
The HPA watched CPU utilization.
```

The failure mode was not:

- Scheduling failure.
- Pod crash.
- OOM kill.
- Probe failure.
- Missing metrics-server.
- Broken HPA object.

The failure mode was:

```text
Autoscaling based on a metric that only weakly represented the bottleneck.
```

In plain language:

```text
The HPA was watching heat, but the service was suffering from waiting.
```

## Better Scaling Signals

For this kind of workload, a better scaling signal would be closer to demand, concurrency, or queueing.

Examples:

```text
in-flight requests per pod
request concurrency per pod
request rate per pod
queue depth
worker pool saturation
dependency wait queue depth
```

Latency is useful as an SLO and alerting signal, but it should be used carefully for autoscaling. Latency can rise for reasons that adding pods will not fix, such as:

```text
slow database query
database saturation
downstream API rate limiting
network problem
lock contention
```

The right question is:

```text
Would adding pods add the scarce capacity?
```

For CPU-bound workloads, CPU is often a good HPA signal. For wait-heavy workloads, request concurrency or queue depth is usually more meaningful.

## Remediation Strategy

### 1. Keep CPU HPA For CPU-Bound Work

CPU-based HPA is still useful when CPU is the real bottleneck.

Example:

```text
image processing
compression
expensive calculations
CPU-heavy request handlers
```

### 2. Add Application Metrics For Wait-Bound Work

For services that spend time waiting on dependencies, expose metrics that represent demand and saturation.

Examples:

```text
active requests
request queue length
worker pool utilization
dependency connection pool utilization
```

### 3. Use External Or Custom Metrics For HPA

A production version could scale on custom or external metrics instead of CPU.

Examples:

```text
average in-flight requests per pod
queue depth per consumer group
requests per second per pod
```

### 4. Validate That Scale-Out Helps

Before changing autoscaling policy, confirm that more pods actually reduce latency.

If the dependency itself is saturated, adding more pods can make the problem worse by sending even more concurrent work downstream.

## Recommended Experiment Follow-up

Add cluster-native k6 Job support and rerun this scenario.

Expected improvement:

```text
Traffic distributes more naturally across pods.
HPA behavior is easier to interpret.
APM latency can be compared against per-pod CPU and replica count.
```

Future advanced option:

```text
Expose in-flight request count as a custom metric and configure HPA to scale on that instead of CPU.
```

## Commands Used For Diagnosis

```bash
make install-metrics-server
make deploy SCENARIO=bad-hpa-signal
kubectl -n scaleops-lab get hpa synthetic-api
kubectl -n scaleops-lab describe hpa synthetic-api
kubectl -n scaleops-lab top pods
kubectl -n scaleops-lab get deploy,pods -o wide
make load-test TEST=latency-spike
make snapshot
```

APM enablement and verification commands:

```bash
make build
make load-image
make install-datadog
kubectl -n scaleops-lab rollout restart deploy/synthetic-api
kubectl -n datadog exec ds/datadog-agent -c agent -- agent status
```

Snapshot captured before APM enablement:

```text
snapshots/20260707-200839
```

## Interview Narrative

A concise explanation:

> I deployed a CPU-based HPA with a 60 percent target and then generated latency using requests that slept for about 900ms while doing only 5ms of CPU work. APM showed the service latency rising to about 923ms p95, but Kubernetes showed healthy pods and the HPA initially stayed at two replicas. Later, after rerunning with APM enabled, the HPA eventually scaled to three replicas because incidental CPU from the request volume briefly crossed the target. That does not mean CPU was the right signal. It means the HPA reacted weakly to a side effect, while the real symptom was request waiting. For this workload, a better scaling signal would be in-flight requests, queue depth, or request concurrency per pod.

Short version:

> The HPA worked, but it was watching a weak proxy for the bottleneck.

## Key Lesson

Autoscaling is only as good as the signal it watches.

A CPU HPA can be healthy, metrics-server can work, and pods can stay Running while users still experience high latency. When latency is caused by dependency waiting or concurrency saturation, CPU may be incidental. Use APM to see the user-facing symptom, then choose a scaling signal that represents the scarce capacity.
