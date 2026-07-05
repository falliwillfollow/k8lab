# Scenario: Bad HPA signal

## Concept

CPU-based autoscaling does not solve every slow request.

## What this scenario changes

Adds an HPA on CPU utilization.

## How to deploy

```bash
make install-metrics-server
make deploy SCENARIO=bad-hpa-signal
```

## How to generate load

```bash
make load-test TEST=latency-spike
```

## What to observe in kubectl

```bash
kubectl -n scaleops-lab get hpa -w
```

Latency rises while CPU may not rise enough to trigger scaling.

## What to observe in Datadog

Latency rises without a matching CPU spike or useful HPA response.

## Diagnosis

The scaling signal does not match the bottleneck.

## Remediation options

Use app metrics, request concurrency, queue depth, dependency fixes, caching, or timeouts.

## Interview narrative

HPA watched CPU, but the bottleneck was artificial latency.

## Cleanup / reset

```bash
make deploy SCENARIO=normal
```

