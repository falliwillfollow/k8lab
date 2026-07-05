# Scenario: Overprovisioned

## Concept

Kubernetes schedules pods based on requested resources, not actual usage.

## What this scenario changes

Sets `4` replicas with very large CPU requests and moderate memory requests. On James' local kind workers, this is intentionally high enough that only some replicas should schedule.

## How to deploy

```bash
make deploy SCENARIO=overprovisioned
```

## How to generate load

Baseline load is enough; the main symptom is scheduling/request waste.

## What to observe in kubectl

```bash
kubectl -n scaleops-lab get pods -o wide
kubectl -n scaleops-lab describe pod <pending-pod>
kubectl describe node <node-name>
```

Look for `Insufficient cpu` or high requested capacity.

## What to observe in Datadog

Requested CPU is high while actual CPU remains low.

## Diagnosis

The scheduler reserves capacity from requests. Excessive requests can block placement even when the node is not busy.

## Remediation options

Lower requests from observed usage plus headroom, reduce replicas, separate workload classes, or add nodes only when real demand justifies it.

## Interview narrative

The node looked underutilized, but pods were Pending because requested CPU was too high.

## Cleanup / reset

```bash
make deploy SCENARIO=normal
```
