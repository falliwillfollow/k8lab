# Scenario: Bad probes

## Concept

Health probes are control-plane inputs. Bad probes can destabilize healthy code.

## What this scenario changes

Makes readiness intermittently fail and points liveness at the same flaky endpoint with aggressive timing.

## How to deploy

```bash
make deploy SCENARIO=bad-probes
```

## How to generate load

Baseline load is enough, but the issue is visible even without load.

## What to observe in kubectl

```bash
kubectl -n scaleops-lab describe pod <pod-name>
kubectl -n scaleops-lab get endpoints synthetic-api -w
kubectl -n scaleops-lab get events --sort-by=.lastTimestamp
```

Look for readiness and liveness failures, endpoint flapping, and restarts.

## What to observe in Datadog

Probe failures, restarts, endpoint instability, and latency/errors.

## Diagnosis

Kubernetes was reacting correctly to a bad signal.

## Remediation options

Keep liveness conservative, make readiness reflect serving capability, avoid fragile dependency checks in liveness, and add startup probes when needed.

## Interview narrative

I would treat probes as active reliability controls, not just monitoring checks.

## Cleanup / reset

```bash
make deploy SCENARIO=normal
```

