# Suggested Datadog Monitors

- `synthetic-api` restart count increases.
- Pod is Pending for more than 5 minutes.
- Container memory usage exceeds 90 percent of limit.
- CPU throttling is sustained for more than 5 minutes.
- p95 latency exceeds the baseline by 2x.
- HPA desired replicas is greater than current replicas for more than 5 minutes.
- Kubernetes warning events contain `Unhealthy`, `FailedScheduling`, or `OOMKilled`.

