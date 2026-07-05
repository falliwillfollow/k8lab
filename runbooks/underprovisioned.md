# Scenario: Underprovisioned

## Concept

Tiny requests improve bin packing on paper but can misrepresent what the app needs.

## What this scenario changes

Sets low requests: `25m` CPU and `64Mi` memory.

## How to deploy

```bash
make deploy SCENARIO=underprovisioned
```

## How to generate load

```bash
make load-test TEST=cpu-spike
make load-test TEST=memory-spike
```

## What to observe in kubectl

Use `kubectl top pods`, restarts, and events. Actual usage should exceed requests under load.

## What to observe in Datadog

Actual usage rises above requested resources. Latency may rise and memory pressure may appear.

## Diagnosis

The app looked cheap to the scheduler but unstable under realistic demand.

## Remediation options

Increase requests, reconsider memory limits, tune CPU limits, add replicas, and validate with latency.

## Interview narrative

Good rightsizing balances cost efficiency with performance and safety margin.

## Cleanup / reset

```bash
make deploy SCENARIO=normal
```

