# Scenario: CPU throttling

## Concept

CPU limits can create latency without obvious errors.

## What this scenario changes

Sets CPU limit to `200m`.

## How to deploy

```bash
make deploy SCENARIO=cpu-throttling
```

## How to generate load

```bash
make load-test TEST=cpu-spike
```

## What to observe in kubectl

Watch pod CPU, logs, and latency. Kubernetes does not expose throttling cleanly through plain `kubectl`, so Datadog is helpful here.

## What to observe in Datadog

Container CPU throttling increases and p95 latency rises.

## Diagnosis

The container wanted more CPU than the limit allowed.

## Remediation options

Raise or remove CPU limits, increase requests for sustained demand, add replicas, or use HPA when CPU is a valid signal.

## Interview narrative

I would distinguish container throttling from node-level CPU exhaustion before changing resources.

## Cleanup / reset

```bash
make deploy SCENARIO=normal
```

