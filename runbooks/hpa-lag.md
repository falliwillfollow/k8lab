# Scenario: HPA works, but too late

## Concept

Autoscaling is reactive and new capacity takes time to become useful.

## What this scenario changes

Adds CPU HPA and a `15` second readiness startup delay.

## How to deploy

```bash
make install-metrics-server
make deploy SCENARIO=hpa-lag
```

## How to generate load

```bash
make load-test TEST=ramp-cpu
```

## What to observe in kubectl

Watch HPA, pods, and readiness:

```bash
kubectl -n scaleops-lab get hpa -w
kubectl -n scaleops-lab get pods -w
```

## What to observe in Datadog

CPU rises, desired replicas increase, then latency stabilizes after new pods become Ready.

## Diagnosis

HPA helped recovery but did not prevent the latency spike.

## Remediation options

Raise min replicas, schedule scaling for known traffic, reduce startup time, improve readiness, or scale on a leading metric.

## Interview narrative

This shows the difference between recovery and prevention.

## Cleanup / reset

```bash
make deploy SCENARIO=normal
```

