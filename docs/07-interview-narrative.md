# Interview Narrative

I built a local Kubernetes failure lab using kind, a synthetic FastAPI workload, k6 load tests, Kustomize overlays, and optional Datadog observability. The lab reproduces overprovisioning, underprovisioning, CPU throttling, memory pressure, bad HPA signals, autoscaling lag, and probe misconfiguration.

The important lesson is that "the site is slow" is not one problem. It could be CPU, memory, scheduling, autoscaling, dependency latency, bad health checks, or application behavior. The fix depends on the evidence.

## Slow Kubernetes App Framework

1. Clarify symptom: latency, errors, saturation, failed deploy, or unavailable service.
2. Scope blast radius: one pod, one deployment, one node, one namespace, or whole cluster.
3. Check recent change: deployment, config, traffic, dependency, resource policy, or node event.
4. Check app signals: request rate, latency, error rate, slow endpoints, logs, traces.
5. Check pod health: restarts, readiness, liveness, OOMKilled, image pulls, Pending pods.
6. Check resources: CPU usage, memory usage, throttling, requests, limits.
7. Check scheduling and scaling: Pending pods, HPA desired/current replicas, metrics availability.
8. Identify bottleneck: CPU, memory, network, dependency, queue, lock contention, bad probe, or bad autoscaling signal.
9. Recommend a tradeoff-aware fix: more resources, better requests, fewer limits, more replicas, better metric, app fix, or dependency fix.
10. Validate outcome with before/after telemetry.

Reusable answer: "I would avoid guessing first. I would define the symptom and blast radius, check recent changes, then line up app metrics, pod health, resources, events, and autoscaling state on the same timeline. If CPU is saturated or throttled, I might change CPU limits, requests, or replicas. If memory crosses limits, I look for OOMKilled and peak usage. If latency rises without CPU, I look at dependencies, queues, locks, or bad scaling signals. Then I validate the fix against the original symptom."

