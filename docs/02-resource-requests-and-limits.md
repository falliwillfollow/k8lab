# Resource Requests And Limits

CPU requests reserve schedulable CPU. CPU limits cap runtime CPU and can cause throttling. Memory requests reserve schedulable memory. Memory limits cap runtime memory and can cause OOMKilled restarts.

Scheduling uses requests, not actual usage. That is why the `overprovisioned` scenario can make the cluster look full even when CPU usage is low. Runtime behavior uses actual demand and limits. That is why the `underprovisioned` and `memory-pressure` scenarios can schedule easily but behave poorly under load.

QoS classes matter during pressure. Guaranteed pods have equal requests and limits for CPU and memory. BestEffort pods have neither. Most real workloads, including this lab, are Burstable: they have some requests and limits but not perfectly equal values.

Good rightsizing balances cost, performance, and safety margin. Use observed p95/p99 usage, latency, restarts, and scaling behavior together.

