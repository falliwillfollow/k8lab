# Bad Probes Scenario Report

## Executive Summary

The `bad-probes` scenario intentionally configured the `synthetic-api` Deployment with fragile health checks:

```text
READY_FAIL_RATE: 0.35
livenessProbe: /readyz
readinessProbe: /readyz
```

This caused Kubernetes to treat intermittent readiness failures as liveness failures. The application process was capable of running, but the kubelet repeatedly restarted containers because `/readyz` sometimes returned `503`.

This demonstrates a core Kubernetes probe concept:

> Readiness controls traffic routing. Liveness controls restarts. Mixing those meanings can turn a temporary readiness issue into a restart loop.

In this run, both pods entered `CrashLoopBackOff`, the Service had no ready endpoints, and baseline traffic failed completely.

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
k8s/base/deployment.yaml
k8s/overlays/bad-probes/patch-probes.yaml
app/synthetic-api/app/main.py
```

The normal base Deployment uses separate probe endpoints:

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: http

readinessProbe:
  httpGet:
    path: /readyz
    port: http
```

The `bad-probes` overlay changes liveness to check the same flaky endpoint as readiness:

```yaml
env:
  - name: READY_FAIL_RATE
    value: "0.35"

livenessProbe:
  httpGet:
    path: /readyz
    port: http
  initialDelaySeconds: 1
  periodSeconds: 3
  timeoutSeconds: 1
  failureThreshold: 1

readinessProbe:
  httpGet:
    path: /readyz
    port: http
  initialDelaySeconds: 1
  periodSeconds: 3
  timeoutSeconds: 1
  failureThreshold: 1
```

The application implements both endpoints:

```text
/healthz: reports that the process is alive
/readyz: reports whether the pod should receive traffic
```

In this scenario, `/readyz` is intentionally flaky. With `READY_FAIL_RATE=0.35`, roughly 35% of readiness checks return `503`.

## Deployment Command

The scenario was deployed with:

```bash
make deploy SCENARIO=bad-probes
```

The rollout completed, but the new pods were already restarting during the rollout:

```text
synthetic-api-685f465896-27rb2   1/1   Running   2 restarts
synthetic-api-685f465896-xgdsh   1/1   Running   2 restarts
```

This was the first sign that the probe configuration was destabilizing otherwise runnable containers.

## Kubernetes Symptoms

Shortly after rollout, both pods became unhealthy:

```text
synthetic-api-685f465896-27rb2   0/1   CrashLoopBackOff   5 restarts
synthetic-api-685f465896-xgdsh   0/1   CrashLoopBackOff   4 restarts
```

Later sampling showed continued restarts:

```text
synthetic-api-685f465896-27rb2   0/1   Running            6 restarts
synthetic-api-685f465896-xgdsh   0/1   CrashLoopBackOff   5 restarts
```

`kubectl describe pod` showed that both probes were checking the same endpoint:

```text
Liveness:   http-get http://:http/readyz delay=1s timeout=1s period=3s #success=1 #failure=1
Readiness:  http-get http://:http/readyz delay=1s timeout=1s period=3s #success=1 #failure=1
```

The container state showed `CrashLoopBackOff`, while the previous termination had exit code `0`:

```text
State:          Waiting
  Reason:       CrashLoopBackOff
Last State:     Terminated
  Reason:       Completed
  Exit Code:    0
Restart Count:  5
```

Interpretation:

```text
The process was not being killed by memory pressure or crashing with an application exception.
Kubernetes was restarting it because the liveness probe failed.
```

## Event Evidence

The Kubernetes event stream showed the exact failure chain:

```text
Warning   Unhealthy   Readiness probe failed: HTTP probe failed with statuscode: 503
Warning   Unhealthy   Liveness probe failed: HTTP probe failed with statuscode: 503
Normal    Killing     Container synthetic-api failed liveness probe, will be restarted
Warning   BackOff     Back-off restarting failed container synthetic-api
```

Some events also showed connection refused while containers were being restarted:

```text
Readiness probe failed: Get "http://10.244.2.18:8080/readyz": dial tcp 10.244.2.18:8080: connect: connection refused
Liveness probe failed: Get "http://10.244.2.18:8080/readyz": dial tcp 10.244.2.18:8080: connect: connection refused
```

Interpretation:

```text
The flaky readiness endpoint caused liveness failures.
The liveness failures caused restarts.
The restarts caused additional probe failures while containers were down.
```

## Service Endpoint Impact

The Service lost ready backends during the probe churn.

At one point only one pod was ready:

```text
endpoints/synthetic-api   10.244.1.18:8080
```

Then no pods were ready:

```text
endpoints/synthetic-api   <empty>
```

The newer EndpointSlice view showed that the pod IPs still existed, but neither endpoint was usable:

```text
addresses:
  - 10.244.2.18
conditions:
  ready: false
  serving: false

addresses:
  - 10.244.1.18
conditions:
  ready: false
  serving: false
```

Interpretation:

```text
The pods still existed, but the Service had no ready backends to route traffic to.
```

## Load Test Results

Baseline load was run with:

```bash
make load-test TEST=baseline
```

The test failed completely:

```text
HTTP requests: 180
Checks succeeded: 0.00%
Checks failed: 100.00%
http_req_failed: 100.00%
```

k6 showed network-level failures:

```text
EOF
dial tcp 127.0.0.1:8080: connect: connection refused
```

Interpretation:

```text
The user-facing symptom was not high latency.
The user-facing symptom was hard request failure because the Service had no stable ready endpoints.
```

## Datadog Symptoms

Useful Datadog signals for this scenario:

```text
Container restart count increasing for synthetic-api pods
Pod status showing CrashLoopBackOff
Kubernetes events with reason:Unhealthy
Liveness and readiness probe failure events
Deployment available replicas dropping below desired replicas
APM request gaps or request failures during the no-endpoint window
```

The most important distinction is that resource metrics are not the root cause. CPU and memory pressure are secondary or absent here. The primary evidence is in probe failures, restarts, pod readiness, and Service endpoint availability.

## HPA Side Note

An HPA object from the previous scenario was still present:

```text
synthetic-api   Deployment/synthetic-api   cpu: <unknown>/50%   min 2   max 8   replicas 2
```

This happened because the workflow applies Kustomize overlays but does not prune objects that are absent from the new overlay.

The HPA was not the cause of this failure. It showed `<unknown>` CPU because the target pods were unready or restarting:

```text
FailedGetResourceMetric        failed to get cpu utilization
FailedComputeMetricsReplicas   did not receive metrics for targeted pods (pods might be unready)
```

For this scenario, the root cause remains the bad probe configuration.

## Diagnosis

The workload was destabilized by incorrect health-check semantics.

Healthy baseline intent:

```text
/healthz answers: is the process alive?
/readyz answers: should this pod receive traffic?
```

Bad scenario behavior:

```text
/readyz sometimes returned 503
livenessProbe checked /readyz
kubelet interpreted transient readiness failures as process death
kubelet restarted the containers
restarts removed pods from readiness
the Service lost ready endpoints
traffic failed
```

This is a configuration-induced availability problem, not a resource-sizing problem.

## Remediation

Recommended fixes:

```text
Point livenessProbe back to /healthz.
Keep liveness conservative and local to the process.
Use readinessProbe for serving capacity and dependency readiness.
Avoid checking fragile external dependencies from liveness.
Use startupProbe for slow-starting applications.
Tune periodSeconds, timeoutSeconds, and failureThreshold to avoid overreacting to short blips.
```

Good target configuration:

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
  failureThreshold: 2
```

## Interview Narrative

If explaining this scenario in an interview:

> The application was not failing because of CPU, memory, or bad code. Kubernetes was being given a bad health signal. Readiness was intentionally flaky, and liveness was incorrectly pointed at that same endpoint. That caused the kubelet to restart containers that should only have been removed from traffic temporarily. I verified the issue through pod restarts, `CrashLoopBackOff`, liveness and readiness probe events, empty Service endpoints, and failed requests. The fix is to separate liveness from readiness: liveness should be conservative and prove the process is not wedged; readiness should decide whether the pod should receive traffic.

## Cleanup

To restore the normal scenario:

```bash
make deploy SCENARIO=normal
```

If the stale HPA object should also be removed after HPA scenarios:

```bash
kubectl -n scaleops-lab delete hpa synthetic-api
```

## Artifacts

Snapshot captured:

```text
snapshots/20260707-210503
```
