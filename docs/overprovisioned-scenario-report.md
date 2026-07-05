# Overprovisioned Workload Scenario Report

## Executive Summary

The `overprovisioned` scenario intentionally configured the `synthetic-api` Deployment with CPU requests far above the workload's actual runtime usage. Kubernetes scheduled some pods, but two replicas remained `Pending` because the scheduler could not find enough allocatable requested CPU on the worker nodes.

This demonstrates a core Kubernetes resource-sizing concept:

> Kubernetes schedules pods based on requested resources, not actual usage.

In this run, the API containers were using only a few millicores of CPU, but each new pod requested `10` CPU cores. The cluster therefore appeared constrained from a scheduling perspective even though runtime CPU usage was low.

## Lab Environment

The lab was running on a local kind cluster.

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
```

Relevant kind configuration:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: scaleops-lab
nodes:
  - role: control-plane
  - role: worker
  - role: worker
```

## Baseline Configuration

The base Deployment defines the normal API workload.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: synthetic-api
  namespace: scaleops-lab
spec:
  replicas: 2
  template:
    metadata:
      labels:
        app.kubernetes.io/name: synthetic-api
        app.kubernetes.io/part-of: scaleops-k8s-failure-lab
        app.kubernetes.io/component: api
        tags.datadoghq.com/env: lab
        tags.datadoghq.com/service: synthetic-api
        tags.datadoghq.com/version: local
      annotations:
        ad.datadoghq.com/synthetic-api.logs: '[{"source":"python","service":"synthetic-api"}]'
    spec:
      containers:
        - name: synthetic-api
          image: synthetic-api:local
          ports:
            - name: http
              containerPort: 8080
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
```

The normal baseline uses small, realistic requests:

```text
Replicas: 2
CPU request per pod: 100m
CPU limit per pod: 500m
Memory request per pod: 128Mi
Memory limit per pod: 512Mi
```

## Overprovisioned Scenario Configuration

The overprovisioned overlay changes the Deployment to request much more CPU.

File:

```text
k8s/overlays/overprovisioned/patch-resources.yaml
```

Configuration:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: synthetic-api
  namespace: scaleops-lab
spec:
  replicas: 4
  template:
    spec:
      containers:
        - name: synthetic-api
          resources:
            requests:
              cpu: "10000m"
              memory: "768Mi"
            limits:
              cpu: "11000m"
              memory: "1Gi"
```

Effective per-pod resource configuration:

```text
CPU request: 10 cores
CPU limit: 11 cores
Memory request: 768Mi
Memory limit: 1Gi
Replica target: 4
```

Effective requested workload if all four replicas scheduled:

```text
Total requested CPU: 40 cores
Total CPU limit: 44 cores
Total requested memory: 3Gi
Total memory limit: 4Gi
```

## Deployment Command

The scenario was deployed with:

```bash
make deploy SCENARIO=overprovisioned
```

The deploy target applies the Kustomize overlay:

```bash
kubectl apply -k k8s/overlays/overprovisioned
kubectl -n scaleops-lab rollout status deploy/synthetic-api --timeout=180s || true
kubectl -n scaleops-lab get pods -o wide
```

The rollout status command timed out because Kubernetes could not complete the rollout.

## Observed Kubernetes State

After deployment, pod state was:

```text
synthetic-api-59d4b5fd8c-ccglq   0/1   Pending
synthetic-api-59d4b5fd8c-fdlb8   1/1   Running   scaleops-lab-worker2
synthetic-api-59d4b5fd8c-kwhq7   0/1   Pending
synthetic-api-59d4b5fd8c-xnk4x   1/1   Running   scaleops-lab-worker
synthetic-api-74c7846ccd-hxdzc   1/1   Running   scaleops-lab-worker2
```

Important behavior:

- Two new high-request pods scheduled successfully.
- Two new high-request pods stayed `Pending`.
- One old pod from the previous ReplicaSet remained Running.
- The Deployment could not fully complete the rolling update.

The old pod remained because Kubernetes was preserving minimum availability during a constrained rollout. This is a useful operational symptom: overprovisioning can stall a rollout, not just create isolated Pending pods.

## Scheduler Event Evidence

The Pending pods showed this scheduler event:

```text
Warning  FailedScheduling
0/3 nodes are available:
1 node(s) had untolerated taint(s),
2 Insufficient cpu.
preemption: 0/3 nodes are available:
1 Preemption is not helpful for scheduling,
2 No preemption victims found for incoming pod.
```

Interpretation:

- The control-plane node was not eligible because it has the normal control-plane `NoSchedule` taint.
- The two worker nodes were eligible, but neither had enough remaining requested CPU capacity.
- Preemption did not help because evicting lower-priority pods was not useful or available for this workload.

## Node Capacity And Requested Resources

Each kind worker had `16` allocatable CPU cores.

```text
scaleops-lab-worker allocatable CPU: 16
scaleops-lab-worker2 allocatable CPU: 16
```

Observed allocated resources:

```text
scaleops-lab-worker:
  synthetic-api high-request pod: 10 CPU requested
  total requested CPU on node: 10200m / 16 cores

scaleops-lab-worker2:
  synthetic-api high-request pod: 10 CPU requested
  old synthetic-api pod: 1500m requested
  total requested CPU on node: 11600m / 16 cores
```

Why another high-request pod could not schedule:

```text
Worker 1:
  16 cores allocatable - 10.2 cores already requested = ~5.8 cores remaining
  Next pod asks for 10 cores
  Result: Insufficient cpu

Worker 2:
  16 cores allocatable - 11.6 cores already requested = ~4.4 cores remaining
  Next pod asks for 10 cores
  Result: Insufficient cpu
```

The control-plane node had capacity, but it was not schedulable for this workload because of its taint:

```text
node-role.kubernetes.io/control-plane:NoSchedule
```

## Runtime Usage Versus Requested Usage

Actual pod CPU usage was tiny compared with requested CPU.

Observed pod usage:

```text
synthetic-api-59d4b5fd8c-fdlb8   ~1-2m CPU
synthetic-api-59d4b5fd8c-xnk4x   ~1-2m CPU
```

Requested CPU:

```text
10,000m CPU per pod
```

This is the key lesson: the scheduler does not care that the process is currently using only a few millicores. It only sees the declared request and reserves schedulable capacity accordingly.

## Datadog Symptoms

Datadog showed the same state from the observability layer:

- Datadog Agent pods were Running.
- `synthetic-api` pods were visible under cluster `scaleops-lab`.
- Two `synthetic-api` pods were `PENDING`.
- Running `synthetic-api` pods remained healthy.
- Kubernetes events showed scheduling failure behavior.

The useful Datadog views for this scenario are:

- Pod list filtered to `namespace:scaleops-lab`.
- Kubernetes events filtered to `synthetic-api` or `FailedScheduling`.
- CPU requested vs CPU used for `synthetic-api`.
- Node allocatable CPU vs requested CPU.
- Deployment/ReplicaSet status for rollout progress.

Expected Datadog interpretation:

```text
Runtime CPU usage is low, but requested CPU is high.
The cluster is constrained from a scheduler perspective, not from actual CPU saturation.
```

## Rollout Behavior

The Deployment strategy was the default rolling update:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 25%
    maxUnavailable: 25%
```

With `replicas: 4`, Kubernetes tried to create replacement pods while keeping the service available. Because only two high-request pods could schedule, the rollout became partially complete:

```text
Desired replicas: 4
Updated replicas: 4
Available replicas: 3
Unavailable replicas: 2
Total pods observed: 5
```

This produced a mixed state:

- Some new pods Running.
- Some new pods Pending.
- One old pod still Running.

That is realistic Kubernetes behavior during a resource-constrained rolling deployment.

## Commands Used For Diagnosis

Useful `kubectl` commands:

```bash
kubectl -n scaleops-lab get pods -o wide
kubectl -n scaleops-lab describe pod synthetic-api-59d4b5fd8c-ccglq
kubectl -n scaleops-lab get events --sort-by=.lastTimestamp
kubectl describe nodes
kubectl -n scaleops-lab top pods
kubectl -n scaleops-lab get deploy synthetic-api -o yaml
```

Snapshot command:

```bash
make snapshot
```

Snapshots captured during this scenario:

```text
snapshots/20260705-130753
snapshots/20260705-131149
```

The later snapshot contains the stronger Pending-pod evidence after the overlay was tuned to request `10000m` CPU per pod.

## Diagnosis

The workload was overprovisioned because each pod requested far more CPU than it needed.

The failure was not caused by:

- Bad container image.
- Application crash.
- Failing liveness probe.
- Failing readiness probe.
- Node runtime CPU saturation.
- Memory pressure.

The failure was caused by:

```text
CPU requests were too large for the worker nodes to fit all desired replicas.
```

Kubernetes correctly refused to place pods that would exceed schedulable requested capacity.

## Remediation Options

Practical remediation choices:

1. Lower CPU requests based on observed usage.
2. Use p95/p99 CPU usage plus headroom instead of worst-case guessing.
3. Reduce replica count if the desired capacity is not actually needed.
4. Add worker nodes only if the demand is real.
5. Use vertical rightsizing recommendations from telemetry.
6. Separate bursty workloads from steady workloads.
7. Review rollout strategy if high requests can temporarily block replacement pods.

For this lab, the immediate reset is:

```bash
make deploy SCENARIO=normal
```

## Interview Narrative

A concise explanation:

> I deployed an intentionally overprovisioned version of the API with 4 replicas, each requesting 10 CPU cores. The app itself was using only a few millicores, but Kubernetes schedules on requests, not actual usage. Two pods became Pending with `Insufficient cpu` events because the worker nodes did not have enough remaining allocatable requested CPU. This shows the difference between runtime utilization and schedulable capacity. I would not immediately add nodes; first I would rightsize requests using observed usage, latency, and reliability headroom.

Short version:

> The cluster was not CPU-saturated at runtime. It was full from the scheduler's point of view.

## What To Look For In Datadog

Use this checklist when reviewing the scenario in Datadog:

- `synthetic-api` Pending pods.
- `FailedScheduling` Kubernetes events.
- Requested CPU far above actual CPU usage.
- Worker nodes showing high requested CPU allocation.
- Deployment rollout not fully converged.
- No matching application error spike required for the scheduling failure.

## Key Lesson

Overprovisioning can make a cluster look full even when workloads are barely using CPU.

Requests are a scheduling contract. If they are too high, Kubernetes reserves capacity the application may never use, which can block deployments, strand capacity, and push teams toward unnecessary node scaling.

