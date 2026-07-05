# Probes

Liveness asks whether Kubernetes should restart a container. Readiness asks whether a pod should receive traffic. Startup probes are useful when a process needs extra time before normal liveness checks apply.

Bad probes are active failure sources, not passive monitoring. If liveness depends on a flaky readiness condition, Kubernetes may restart healthy processes. If readiness is too aggressive, the Service endpoint list can flap and users may see errors.

In `bad-probes`, `/readyz` fails intermittently and liveness points at it. Watch `kubectl describe pod` and events to see Kubernetes react to the bad signal.

