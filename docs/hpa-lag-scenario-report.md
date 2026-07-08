# HPA Lag Scenario Report

## Executive Summary

The `hpa-lag` scenario configured a CPU-based Horizontal Pod Autoscaler and added an intentional `15` second readiness delay to the `synthetic-api` pods.

Under a ramping CPU load, the HPA reacted correctly: it detected CPU above target and scaled the Deployment from `2` replicas to `4`, then to `8`. However, new pods were not immediately useful. They had to be created, started, and pass readiness before they could receive traffic. During that lag window, request latency rose.

This demonstrates a core autoscaling concept:

> HPA is reactive. Scaling decisions happen before new capacity is actually Ready.

In this run, HPA also overshot to the maximum replica count because demand remained high while newly created pods were still warming up.

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
k8s/overlays/hpa-lag/patch-resources.yaml
k8s/overlays/hpa-lag/hpa.yaml
```

Deployment resource and readiness-delay configuration:

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
          env:
            - name: READY_STARTUP_DELAY_SECONDS
              value: "15"
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "800m"
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
          averageUtilization: 50
```

Effective autoscaling policy:

```text
Minimum replicas: 2
Maximum replicas: 8
Scaling signal: average CPU utilization
Target CPU utilization: 50%
CPU request per pod: 100m
Approximate target CPU per pod: 50m
Readiness startup delay: 15 seconds
```

## Deployment Command

The scenario was deployed with:

```bash
make install-metrics-server
make deploy SCENARIO=hpa-lag
```

The rollout itself showed the effect of the readiness delay:

```text
Waiting for deployment "synthetic-api" rollout to finish...
deployment "synthetic-api" successfully rolled out
```

Initial HPA state after rollout:

```text
synthetic-api   Deployment/synthetic-api   cpu: 2%/50%   min 2   max 8   replicas 2
```

Initial pod state:

```text
synthetic-api-5c5bbc7f85-c4lpd   1/1   Running
synthetic-api-5c5bbc7f85-djvfx   1/1   Running
```

## Load Test Configuration

File:

```text
load/k6/ramp-cpu.js
```

Load test:

```javascript
export const options = {
  stages: [
    { duration: '30s', target: 4 },
    { duration: '60s', target: 16 },
    { duration: '60s', target: 24 },
    { duration: '30s', target: 0 },
  ],
};

export default function () {
  const res = http.get(`${BASE_URL}/work?cpu_ms=250&memory_mb=1&sleep_ms=0`, { timeout: '10s' });
  check(res, { 'request completed': (r) => r.status < 500 });
  sleep(0.2);
}
```

Command:

```bash
make load-test TEST=ramp-cpu
```

This generated increasing CPU-bound request pressure over three minutes.

## k6 Results

The ramp completed without request failures, but latency rose while the system was under CPU pressure and scaling.

```text
Requests: 2196
Error rate: 0.00%
Average latency: 793.41ms
p90 latency: 1.18s
p95 latency: 1.34s
Max latency: 2.26s
```

Interpretation:

```text
The service stayed available.
The service became slower while HPA reacted and new pods warmed up.
```

## HPA Timeline

The HPA started at `2` replicas:

```text
cpu: 2%/50%   replicas: 2
```

During the ramp, HPA saw CPU far above target:

```text
20:42:41   cpu: 203%/50%   replicas: 2
20:42:56   cpu: 293%/50%   replicas: 4
20:43:12   cpu: 392%/50%   replicas: 8
20:43:27   cpu: 385%/50%   replicas: 8
20:43:42   cpu: 195%/50%   replicas: 8
20:43:57   cpu: 118%/50%   replicas: 8
20:44:12   cpu: 105%/50%   replicas: 8
20:44:27   cpu: 110%/50%   replicas: 8
```

HPA events confirmed the scale-up decisions:

```text
SuccessfulRescale   New size: 4; reason: cpu resource utilization above target
SuccessfulRescale   New size: 8; reason: cpu resource utilization above target
```

Final HPA state:

```text
current CPU: 99% / target 50%
current replicas: 8
desired replicas: 8
ScalingLimited: True
Reason: TooManyReplicas
Message: desired replica count is more than the maximum replica count
```

Interpretation:

```text
HPA wanted more capacity, but it had already reached maxReplicas.
```

## Readiness Lag Evidence

The new pods existed before they were useful.

At `20:42:41`, HPA had already created new pods, but they were not Ready:

```text
synthetic-api-5c5bbc7f85-4s9zv   0/1   Running
synthetic-api-5c5bbc7f85-jqf92   0/1   Running
```

At `20:42:56`, the HPA had scaled further, and more new pods were still not Ready:

```text
synthetic-api-5c5bbc7f85-jk945   0/1   Running
synthetic-api-5c5bbc7f85-jtzsm   0/1   Running
synthetic-api-5c5bbc7f85-lshvm   0/1   Running
synthetic-api-5c5bbc7f85-tccxl   0/1   Running
```

Kubernetes events showed the intentional readiness failures:

```text
Warning   Unhealthy   Readiness probe failed: HTTP probe failed with statuscode: 503
```

Interpretation:

```text
The pods had started, but readiness correctly kept them out of service until the startup delay passed.
```

This is the lag: desired capacity existed in Kubernetes object state before it became serving capacity.

## Why HPA Overshot

HPA can overshoot when demand rises faster than useful capacity comes online.

The loop in this scenario was:

```text
1. Demand increased.
2. Existing Ready pods became CPU hot.
3. HPA saw CPU above target.
4. HPA increased desired replicas.
5. New pods were created.
6. New pods were not Ready yet because of the 15-second startup delay.
7. Existing Ready pods still carried most of the load.
8. HPA sampled again and still saw high CPU.
9. HPA scaled up again.
```

That is how the system moved quickly from `2` replicas to `4`, then to the maximum of `8`.

This is not necessarily a Kubernetes bug. It is a tradeoff:

```text
Aggressive scale-up can recover faster from real spikes.
Slow startup or uneven traffic can make HPA temporarily overprovision.
```

## Datadog Symptoms

Datadog APM showed the user-facing latency spike during the same time window.

Useful APM metric:

```text
avg:trace.fastapi.request{*}
```

Observed APM pattern:

```text
20:42 demand started ramping
20:43 latency climbed
20:44 latency peaked around 0.8-0.9 seconds
20:45 latency dropped as load ramped down and capacity had caught up
```

This correlated with the Kubernetes timeline:

```text
20:42:41 HPA saw 203%/50%, new pods existed but some were 0/1 Ready
20:42:56 HPA saw 293%/50%, more pods were created and warming
20:43:12 HPA reached 8 replicas
20:43-20:44 latency remained elevated
20:45 load ended and latency dropped
```

The APM evidence was important because Kubernetes metrics showed CPU and readiness state, while APM showed the user-facing request latency.

## Load Distribution Caveat

The load test used local `kubectl port-forward` against the Kubernetes Service:

```bash
kubectl -n scaleops-lab port-forward svc/synthetic-api 8080:80
```

In this run, traffic again concentrated mostly on one backend pod.

During and after scale-up, one pod stayed much hotter than the rest:

```text
synthetic-api-5c5bbc7f85-djvfx   ~768m-800m CPU
most other pods                  ~2m-27m CPU
```

This means the scenario still demonstrated HPA lag, but the additional replicas did not help as much as they would under more realistic in-cluster load balancing.

A better future experiment would run k6 inside the cluster as a Kubernetes Job so traffic goes through normal in-cluster Service routing.

## Diagnosis

The HPA was configured correctly and reacted to CPU pressure.

The failure mode was not:

- Missing metrics-server.
- Broken HPA object.
- Pod crash.
- OOM kill.
- Scheduling failure.

The failure mode was:

```text
Reactive autoscaling lag plus readiness delay before new pods became usable capacity.
```

In plain language:

```text
HPA helped recovery, but it could not prevent the latency spike.
```

## Remediation Strategy

### 1. Raise minReplicas

If traffic spikes are common, keep more warm capacity online.

Example:

```text
minReplicas: 4
```

This costs more idle capacity but reduces the amount of reactive scale-up needed.

### 2. Reduce Startup And Readiness Time

Shorter startup paths reduce the gap between desired replicas and Ready replicas.

Potential improvements:

```text
optimize app startup
defer noncritical initialization
warm caches asynchronously
tune readiness to reflect true serving ability
```

### 3. Use Scheduled Or Predictive Scaling

If spikes are predictable, scale before demand arrives.

Examples:

```text
business-hours traffic
batch windows
known campaign launches
daily cron-driven demand
```

### 4. Scale On A Leading Signal

CPU is reactive. Queue depth or request backlog can sometimes show demand before CPU fully reflects it.

Examples:

```text
queue depth
in-flight requests
request backlog
work arrival rate
```

### 5. Configure HPA Behavior Policies

Kubernetes HPA supports scale-up and scale-down behavior policies. These can tune how aggressively HPA adds or removes replicas.

For this scenario, aggressive scale-up reached max replicas quickly. In production, the right policy depends on whether latency risk or temporary overprovisioning is more expensive.

## Recommended Experiment Follow-up

Add cluster-native k6 Job support and rerun this scenario.

Expected improvement:

```text
Traffic spreads more naturally across Ready pods.
HPA scale-up impact is easier to observe.
APM latency should better reflect capacity coming online.
```

Then compare:

```text
time to first scale-up
time from pod creation to Ready
latency before and after readiness
CPU distribution across pods
replica overshoot
```

## Commands Used For Diagnosis

```bash
make install-metrics-server
make deploy SCENARIO=hpa-lag
kubectl -n scaleops-lab get hpa synthetic-api
kubectl -n scaleops-lab describe hpa synthetic-api
kubectl -n scaleops-lab get pods -o wide
kubectl -n scaleops-lab top pods
kubectl -n scaleops-lab get events --sort-by=.lastTimestamp
make load-test TEST=ramp-cpu
make snapshot
```

Snapshot captured:

```text
snapshots/20260707-204515
```

## Interview Narrative

A concise explanation:

> I deployed a CPU-based HPA with a 50 percent target and added a 15-second readiness startup delay. Under ramping CPU load, HPA reacted correctly and scaled the Deployment from two replicas to four, then to eight. But some new pods were Running while still 0/1 Ready, so they were not yet serving traffic. During that window, APM showed latency rising and k6 p95 reached about 1.34 seconds. The HPA eventually reached max replicas because it kept sampling high CPU before earlier scale-up decisions had become useful capacity. This shows that autoscaling can help recovery without preventing a latency spike.

Short version:

> HPA made the right decision, but the new capacity arrived late.

## Key Lesson

Autoscaling is not instant capacity.

HPA has to observe load, calculate desired replicas, update the Deployment, wait for pods to start, and wait for readiness. If startup or readiness takes time, HPA may continue to see overloaded old capacity and scale further. That can cause temporary overshoot, but it is often preferable to staying under capacity during a real spike.
