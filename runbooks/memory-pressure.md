# Scenario: Memory pressure

## Concept

CPU can throttle; memory over a limit can kill the container.

## What this scenario changes

Sets memory limit to `256Mi`.

## How to deploy

```bash
make deploy SCENARIO=memory-pressure
```

## How to generate load

```bash
make load-test TEST=memory-spike
```

## What to observe in kubectl

```bash
kubectl -n scaleops-lab get pods
kubectl -n scaleops-lab describe pod <pod-name>
kubectl -n scaleops-lab get events --sort-by=.lastTimestamp
```

Look for restarts and `OOMKilled`.

## What to observe in Datadog

Memory spike, restart event, and container termination reason.

## Diagnosis

Memory sizing needs peak analysis because exceeding the limit terminates the process.

## Remediation options

Increase memory limit/request, investigate leaks, add app controls, and avoid limits too close to normal peaks.

## Interview narrative

The failure changed from slowness to restarts, so I would inspect last termination state and memory trends.

## Cleanup / reset

```bash
make deploy SCENARIO=normal
```

