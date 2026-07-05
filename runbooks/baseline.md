# Scenario: Normal baseline

## Concept

Healthy first, failures second. Establish stable replicas, low latency, no restarts, and sane resource use.

## What this scenario changes

Replicas are `2`, requests are `100m` CPU and `128Mi` memory, and limits are `500m` CPU and `512Mi` memory.

## How to deploy

```bash
make deploy SCENARIO=normal
```

## How to generate load

```bash
make load-test TEST=baseline
```

## What to observe in kubectl

Pods should be Running and Ready. `make status` should show no restarts and no warning events.

## What to observe in Datadog

Low latency, low error rate, modest CPU and memory, no restart or OOM events.

## Diagnosis

This is the known-good reference for later comparison.

## Remediation options

None. Use this scenario to reset after experiments.

## Interview narrative

Before diagnosing failure modes, I established what healthy looked like.

## Cleanup / reset

Redeploy with `make deploy SCENARIO=normal`.

