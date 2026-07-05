# Datadog Observability

Use Datadog to correlate Kubernetes state with runtime pressure and app behavior.

For overprovisioning, compare requested CPU and memory against actual usage. For underprovisioning, compare actual usage against requests, latency, and restarts. For CPU throttling, graph container CPU throttling with p95 latency. For memory pressure, look for memory spikes, restarts, and OOMKilled events. For HPA scenarios, graph current replicas, desired replicas, CPU utilization, and latency on the same timeline.

Logs from `synthetic-api` include path, status, latency, and pod name. Use them to connect a slow endpoint to the pod and the Kubernetes event timeline.

APM is enabled in the Datadog values, but local kind networking can vary. Treat traces as useful optional polish, not a blocker for the core lab.

