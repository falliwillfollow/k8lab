# Autoscaling

The Horizontal Pod Autoscaler changes replica count based on metrics. In this lab it uses CPU utilization, which depends on metrics-server and CPU requests. If requests are missing or metrics-server is unavailable, CPU HPA cannot make good decisions.

HPA is reactive. It waits for metrics, changes desired replicas, the scheduler places pods, containers start, readiness passes, and traffic shifts. `hpa-lag` makes that delay visible.

The scaling signal must match the bottleneck. `bad-hpa-signal` creates latency with sleep, so CPU does not rise much and CPU-based HPA does not help. Horizontal scaling adds pods. Vertical scaling changes pod resources.

