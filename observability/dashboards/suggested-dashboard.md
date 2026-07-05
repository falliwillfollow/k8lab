# Suggested Datadog Dashboard

Build one dashboard named `ScaleOps K8s Failure Lab`.

## Cluster capacity

- Node CPU usage and node memory usage.
- CPU requested vs allocatable, grouped by node.
- Memory requested vs allocatable, grouped by node.
- Pod count by node.

## Workload health

- Desired replicas and available replicas for `synthetic-api`.
- Pod restart count and container restart count.
- Pending pods and Kubernetes warning events.
- OOMKilled events.

## Runtime pressure

- Container CPU usage for `synthetic-api`.
- CPU throttling for `synthetic-api`.
- Container memory usage.
- Memory limit utilization.

## App behavior

- Request rate from logs or Prometheus metrics.
- Error rate by status.
- p50, p95, and p99 latency.
- Slow endpoint breakdown for `/work`, `/cpu`, `/memory`, and `/leak`.

## Autoscaling

- HPA current replicas and desired replicas.
- HPA target metric and current metric.
- Timeline markers for load tests and deploys.

## Events timeline

Overlay Kubernetes events with resource graphs. The useful story is usually in the timing: deploy, scheduling failure, probe failure, restart, OOM kill, or scale event.

