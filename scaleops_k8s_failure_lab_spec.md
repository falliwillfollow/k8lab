# ScaleOps Kubernetes Failure Lab

**Purpose:** Build a local Kubernetes learning lab that teaches core Kubernetes concepts through observable failure modes: overprovisioning, underprovisioning, CPU throttling, memory pressure, bad autoscaling signals, autoscaling lag, and probe misconfiguration.

**Primary audience:** A coding agent implementing the lab for James Mearns as preparation for a ScaleOps TAM technical interview.

**Desired outcome:** A runnable local Kubernetes project that lets the user deploy a small synthetic workload, trigger controlled failure conditions, observe symptoms in `kubectl` and Datadog, and practice explaining remediation tradeoffs.

---

## 1. Project framing

This is not a generic Kubernetes demo. It is a **Kubernetes performance failure lab**.

The lab should help the user say, credibly:

> I built a local Kubernetes lab that reproduces common workload-sizing and autoscaling failure modes. I instrumented the cluster with Datadog, created controlled resource problems, observed the symptoms, and practiced diagnosing tradeoffs between cost, performance, reliability, and scaling behavior.

The coding agent should optimize for:

1. **Learning clarity** over infrastructure cleverness.
2. **Repeatable failure scenarios** over one-off manual experiments.
3. **Datadog-observable symptoms** over purely local CLI output.
4. **Interview narrative value** over production-grade complexity.

---

## 2. Non-goals

Do **not** overbuild this project.

Avoid the following unless explicitly requested later:

- No raw `kubeadm` cluster setup.
- No cloud cluster provisioning.
- No Terraform.
- No service mesh.
- No ingress controller unless needed for a simple optional UI.
- No Argo CD, Flux, or GitOps stack.
- No complex microservices demo.
- No custom Kubernetes operators.
- No production-grade security hardening beyond reasonable defaults.
- No opaque automation that hides Kubernetes concepts from the learner.

The point is to understand Kubernetes behavior, not to create a miniature enterprise platform.

---

## 3. Recommended local platform

Use **kind** as the default local cluster provider.

Rationale:

- It runs Kubernetes locally using Docker containers as nodes.
- It is common in development and interview-prep contexts.
- It supports multi-node clusters.
- It keeps the project reproducible and disposable.
- It avoids the deeper operational burden of `kubeadm`.

The lab should be designed so that k3d or minikube could be added later, but the initial implementation should support kind only.

Target host:

- Ubuntu Linux or similar Linux distribution.
- Docker installed and running.
- User has access to a Datadog sandbox and API key.

---

## 4. Required tools

The project should check for these tools and provide installation guidance if missing:

- `docker`
- `kubectl`
- `kind`
- `helm`
- `make`
- `jq`
- `curl`

Optional but useful:

- `watch`
- `stern` or `kubetail` for logs
- Datadog CLI, only if genuinely useful

Do not embed secrets in the repo.

---

## 5. Repository structure

Create a repository with this structure:

```text
scaleops-k8s-failure-lab/
  README.md
  Makefile
  .gitignore
  .env.example

  app/
    synthetic-api/
      Dockerfile
      requirements.txt
      app/
        main.py
        load.py
        metrics.py

  cluster/
    kind-config.yaml
    metrics-server.yaml

  k8s/
    base/
      namespace.yaml
      deployment.yaml
      service.yaml
      configmap.yaml
      kustomization.yaml

    overlays/
      normal/
        kustomization.yaml
        patch-resources.yaml

      overprovisioned/
        kustomization.yaml
        patch-resources.yaml
        README.md

      underprovisioned/
        kustomization.yaml
        patch-resources.yaml
        README.md

      cpu-throttling/
        kustomization.yaml
        patch-resources.yaml
        README.md

      memory-pressure/
        kustomization.yaml
        patch-resources.yaml
        README.md

      bad-hpa-signal/
        kustomization.yaml
        hpa.yaml
        patch-resources.yaml
        README.md

      hpa-lag/
        kustomization.yaml
        hpa.yaml
        patch-resources.yaml
        README.md

      bad-probes/
        kustomization.yaml
        patch-probes.yaml
        README.md

  load/
    k6/
      baseline.js
      cpu-spike.js
      memory-spike.js
      latency-spike.js
      ramp-cpu.js
      run-k6-job.yaml

  observability/
    datadog-values.yaml
    dashboards/
      suggested-dashboard.md
    monitors/
      suggested-monitors.md

  scripts/
    check-prereqs.sh
    create-cluster.sh
    delete-cluster.sh
    build-and-load-image.sh
    install-metrics-server.sh
    install-datadog.sh
    deploy-scenario.sh
    run-load.sh
    collect-debug-snapshot.sh

  docs/
    00-learning-path.md
    01-core-kubernetes-concepts.md
    02-resource-requests-and-limits.md
    03-scheduler-and-pending-pods.md
    04-autoscaling.md
    05-probes.md
    06-datadog-observability.md
    07-interview-narrative.md

  runbooks/
    scenario-template.md
    overprovisioned.md
    underprovisioned.md
    cpu-throttling.md
    memory-pressure.md
    bad-hpa-signal.md
    hpa-lag.md
    bad-probes.md
```

---

## 6. Environment configuration

Create `.env.example`:

```bash
# Datadog configuration
DD_API_KEY="replace_me"
DD_SITE="datadoghq.com"

# Optional Datadog app key if dashboard or monitor automation is later added
DD_APP_KEY="replace_me_optional"

# Local lab settings
CLUSTER_NAME="scaleops-lab"
NAMESPACE="scaleops-lab"
APP_IMAGE="synthetic-api:local"
```

The implementation should load `.env` when present, but must not require Datadog for the core Kubernetes scenarios to run.

Acceptance criteria:

- The project runs without Datadog, using `kubectl` only.
- When Datadog variables are present, the Datadog Agent can be installed.
- No secret values are committed.

---

## 7. Makefile interface

Implement the following top-level commands:

```bash
make help
make check
make cluster-up
make cluster-down
make build
make load-image
make install-metrics-server
make install-datadog
make deploy SCENARIO=normal
make status
make logs
make load-test TEST=baseline
make snapshot
make clean
```

Each command should print a short teaching note before executing.

Example:

```bash
make deploy SCENARIO=overprovisioned
```

Should print something like:

```text
Concept: Kubernetes schedules pods based on requested resources, not actual usage.
Deploying scenario: overprovisioned
```

This is important. The Makefile is not just automation. It is part of the teaching layer.

---

## 8. Cluster design

Create a kind cluster with one control-plane node and two worker nodes.

`cluster/kind-config.yaml` should approximate:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: scaleops-lab
nodes:
  - role: control-plane
  - role: worker
  - role: worker
```

The coding agent may add extra config only if necessary.

Acceptance criteria:

- `make cluster-up` creates the cluster.
- `kubectl get nodes` shows at least three nodes.
- `make cluster-down` deletes the cluster cleanly.

---

## 9. Synthetic API requirements

Build a small Python FastAPI service.

The service should expose these endpoints:

### `GET /healthz`

Purpose: basic liveness endpoint.

Behavior:

- Always returns `200 OK` unless the process is truly broken.

### `GET /readyz`

Purpose: readiness endpoint.

Behavior:

- Returns `200 OK` by default.
- Can be configured through environment variables to fail intermittently or during startup.

Suggested environment variables:

```bash
READY_FAIL_RATE="0.0"
READY_STARTUP_DELAY_SECONDS="0"
```

### `GET /work`

Purpose: combined synthetic work endpoint.

Query parameters:

- `cpu_ms`: approximate CPU burn duration in milliseconds.
- `memory_mb`: approximate memory allocation in megabytes.
- `sleep_ms`: artificial latency in milliseconds.
- `status`: optional HTTP status code to return.

Example:

```text
/work?cpu_ms=200&memory_mb=20&sleep_ms=100&status=200
```

### `GET /cpu`

Purpose: generate CPU pressure.

Query parameters:

- `seconds`: CPU burn duration.

Example:

```text
/cpu?seconds=10
```

### `GET /memory`

Purpose: generate temporary memory pressure.

Query parameters:

- `mb`: amount of memory to allocate.
- `hold_seconds`: how long to hold it.

Example:

```text
/memory?mb=300&hold_seconds=20
```

### `GET /leak`

Purpose: simulate memory leak behavior.

Query parameters:

- `mb`: amount of memory to permanently retain in process memory.

Example:

```text
/leak?mb=50
```

### `GET /metrics`

Purpose: expose Prometheus-style app metrics.

Use `prometheus_client` if practical.

Suggested custom metrics:

- request count by path/status
- request latency histogram
- synthetic CPU work count
- synthetic memory allocation count
- current leaked memory MB

Acceptance criteria:

- App builds as a Docker image.
- App runs locally with Docker.
- App runs as a Kubernetes Deployment.
- App logs request path, status, latency, and pod name.
- `/metrics` exposes useful metrics.

---

## 10. Kubernetes base manifest

The base deployment should include:

- Namespace: `scaleops-lab`
- Deployment: `synthetic-api`
- Service: `synthetic-api`
- ConfigMap for app config
- Reasonable default resources
- Liveness probe
- Readiness probe
- Labels suitable for Datadog and Kubernetes filtering

Required labels:

```yaml
app.kubernetes.io/name: synthetic-api
app.kubernetes.io/part-of: scaleops-k8s-failure-lab
app.kubernetes.io/component: api
```

Datadog unified service tags should also be present where useful:

```yaml
tags.datadoghq.com/env: lab
tags.datadoghq.com/service: synthetic-api
tags.datadoghq.com/version: local
```

Base resources should be conservative:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
```

Acceptance criteria:

- `make deploy SCENARIO=normal` works.
- `kubectl -n scaleops-lab get pods` shows healthy pods.
- Service can be port-forwarded locally.
- Basic requests to `/healthz`, `/readyz`, and `/work` succeed.

---

## 11. Load generation

Use k6 for repeatable load tests.

Each load script should be understandable and small.

Required tests:

### `baseline.js`

Purpose: normal traffic.

Expected behavior:

- Low latency.
- Low error rate.
- No scaling events.
- No restarts.

### `cpu-spike.js`

Purpose: sustained CPU pressure.

Expected behavior:

- CPU rises.
- Latency rises if resources are constrained.
- HPA may react if enabled.

### `memory-spike.js`

Purpose: temporary memory pressure.

Expected behavior:

- Memory usage rises.
- If memory limit is too low, pod may be OOMKilled.

### `latency-spike.js`

Purpose: simulate slow app behavior without high CPU.

Expected behavior:

- Latency rises.
- CPU may remain low.
- CPU-based HPA may not react.

### `ramp-cpu.js`

Purpose: gradual ramp to show autoscaling lag.

Expected behavior:

- Load increases gradually.
- HPA eventually increases replicas.
- Latency may spike before additional pods become ready.

Implementation options:

- Run k6 locally against a port-forwarded service.
- Also support running k6 as a Kubernetes Job for a more cluster-native workflow.

Acceptance criteria:

- `make load-test TEST=baseline` runs successfully.
- `make load-test TEST=cpu-spike` creates visible CPU impact.
- Load scripts are documented and easy to modify.

---

## 12. Datadog integration

Implement Datadog as an optional but first-class observability layer.

Use Helm to install the Datadog Agent.

Create `observability/datadog-values.yaml` with values for:

- Kubernetes metrics
- kube-state-metrics core
- logs collection
- APM if feasible
- process collection if useful
- cluster name: `scaleops-lab`

The installation script should:

1. Validate that `DD_API_KEY` is present.
2. Create a `datadog` namespace.
3. Create or update a Kubernetes secret for the API key.
4. Add/update the Datadog Helm repo.
5. Install or upgrade the Datadog chart.
6. Print validation commands.

Do not hardcode the user's Datadog site. Use `DD_SITE` from `.env`, defaulting to `datadoghq.com`.

Acceptance criteria:

- `make install-datadog` installs the agent when `.env` is configured.
- Datadog pods become healthy.
- Kubernetes nodes, pods, and containers appear in Datadog.
- Logs from `synthetic-api` appear in Datadog if logs are enabled.
- If APM is implemented, traces from `synthetic-api` appear under service `synthetic-api`.

If APM proves unreliable in local kind networking, document it as optional and do not block the core project.

---

## 13. Observability expectations

Create `observability/dashboards/suggested-dashboard.md` describing the dashboard the user should build or import.

The dashboard should include these sections:

### Cluster capacity

- Node CPU usage
- Node memory usage
- CPU requested vs allocatable
- Memory requested vs allocatable
- Pod count by node

### Workload health

- Desired replicas
- Available replicas
- Pod restart count
- Pending pods
- OOMKilled events
- Container restarts

### Runtime pressure

- Container CPU usage
- CPU throttling
- Container memory usage
- Memory limit utilization

### App behavior

- Request rate
- Error rate
- p50/p95/p99 latency
- Slow endpoints

### Autoscaling

- HPA current replicas
- HPA desired replicas
- HPA target metric
- HPA current metric

### Events timeline

- Deployments
- Pod scheduling failures
- Probe failures
- OOM kills
- Scaling events

Acceptance criteria:

- The docs identify what the user should look for in each scenario.
- Dashboard guidance is specific enough for manual setup if API automation is not implemented.
- Dashboard automation is optional, not required for MVP.

---

## 14. Scenario design

Each scenario must include:

- A Kustomize overlay.
- A README.
- A runbook.
- Expected symptoms in `kubectl`.
- Expected symptoms in Datadog.
- Interview explanation.
- Remediation options.

Use this standard structure for every scenario runbook:

```markdown
# Scenario: <name>

## Concept

## What this scenario changes

## How to deploy

## How to generate load

## What to observe in kubectl

## What to observe in Datadog

## Diagnosis

## Remediation options

## Interview narrative

## Cleanup / reset
```

---

## 15. Scenario A: Normal baseline

Path:

```text
k8s/overlays/normal/
runbooks/baseline.md
```

Purpose:

Establish a known-good baseline.

Configuration:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
replicas: 2
```

Expected behavior:

- Pods are Running and Ready.
- No restarts.
- Low latency under baseline load.
- CPU and memory usage remain below limits.

Interview narrative:

> Before diagnosing failure modes, I established a baseline so I knew what healthy looked like: stable replicas, low latency, no restarts, and resource usage safely below limits.

Acceptance criteria:

- Baseline load test completes with low error rate.
- User can identify healthy signals in both `kubectl` and Datadog.

---

## 16. Scenario B: Overprovisioned workload

Path:

```text
k8s/overlays/overprovisioned/
runbooks/overprovisioned.md
```

Purpose:

Show how excessive requests waste cluster capacity and prevent scheduling, even when actual usage is low.

Configuration:

```yaml
resources:
  requests:
    cpu: "1500m"
    memory: "768Mi"
  limits:
    cpu: "2000m"
    memory: "1Gi"
replicas: 4
```

The exact values may need adjustment depending on local node capacity. The goal is to create scheduling pressure.

Expected behavior:

- Some pods may become Pending if requested resources exceed available allocatable capacity.
- Actual CPU usage remains low.
- Datadog shows a gap between requested CPU and actual CPU usage.
- Cluster appears full from a scheduler perspective, not from actual utilization.

Commands to inspect:

```bash
kubectl -n scaleops-lab get pods -o wide
kubectl -n scaleops-lab describe pod <pending-pod>
kubectl describe node <node-name>
```

Likely event message:

```text
Insufficient cpu
```

Diagnosis:

Kubernetes schedules based on requests. If requests are too high, the scheduler reserves capacity that the app may never actually use.

Remediation options:

- Lower requests based on observed p95/p99 usage plus headroom.
- Use vertical rightsizing recommendations.
- Separate bursty workloads from steady workloads.
- Revisit replica count.
- Add nodes only if real usage justifies it.

Interview narrative:

> The node looked underutilized, but pods were Pending because the workload requested too much CPU. This is the difference between runtime utilization and schedulable capacity. The fix is not blindly adding nodes. First I would rightsize requests based on observed usage and reliability needs.

Acceptance criteria:

- The scenario visibly demonstrates scheduling pressure or obvious request/usage waste.
- The runbook explains the distinction between requested and actual resources.

---

## 17. Scenario C: Underprovisioned workload

Path:

```text
k8s/overlays/underprovisioned/
runbooks/underprovisioned.md
```

Purpose:

Show what happens when requests are too low and the workload is packed too aggressively.

Configuration:

```yaml
resources:
  requests:
    cpu: "25m"
    memory: "64Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
replicas: 2
```

Expected behavior:

- Pods schedule easily because requests are tiny.
- Under load, actual usage far exceeds requests.
- Latency may rise.
- If memory usage crosses limit, OOM kills may occur.
- If CPU limit is hit, throttling may occur.

Load test:

```bash
make load-test TEST=cpu-spike
make load-test TEST=memory-spike
```

Diagnosis:

Low requests can improve bin packing on paper, but they may misrepresent what the app needs to behave reliably.

Remediation options:

- Increase requests to a realistic baseline.
- Avoid setting memory limits below realistic peak memory.
- Evaluate whether CPU limits are helping or causing throttling.
- Use observed usage and latency together, not usage alone.

Interview narrative:

> The app looked cheap to the scheduler, but it was unstable under realistic load. This shows the risk of optimizing only for packing density. Good rightsizing balances cost efficiency with performance and safety margin.

Acceptance criteria:

- User can observe actual usage exceeding requested usage.
- User can explain why low requests can be dangerous.

---

## 18. Scenario D: CPU throttling

Path:

```text
k8s/overlays/cpu-throttling/
runbooks/cpu-throttling.md
```

Purpose:

Show how CPU limits can throttle a container and increase latency.

Configuration:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "200m"
    memory: "512Mi"
replicas: 2
```

Expected behavior:

- CPU usage approaches the limit.
- Throttling metrics increase.
- Request latency rises.
- Error rate may remain low, making the problem look like “just slowness.”

Load test:

```bash
make load-test TEST=cpu-spike
```

Diagnosis:

CPU limits can create artificial ceilings. The pod may need more CPU during bursts, but the limit prevents it from using available node CPU.

Remediation options:

- Raise or remove CPU limits depending on organizational policy.
- Increase requests if sustained CPU need is real.
- Add replicas if the workload is horizontally scalable.
- Use HPA if CPU is a valid scaling signal.

Interview narrative:

> The service was slow without necessarily failing. The key signal was CPU throttling. That tells me the container wanted more CPU than the limit allowed. I would distinguish this from node-level CPU exhaustion before recommending a fix.

Acceptance criteria:

- CPU throttling is visible in either Datadog or available Kubernetes/container metrics.
- Latency increases under CPU load.

---

## 19. Scenario E: Memory pressure and OOMKilled

Path:

```text
k8s/overlays/memory-pressure/
runbooks/memory-pressure.md
```

Purpose:

Show how memory limits behave differently from CPU limits.

Configuration:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
replicas: 2
```

Load test:

```bash
make load-test TEST=memory-spike
```

Expected behavior:

- Memory usage approaches the limit.
- One or more pods may restart.
- Pod status may show `OOMKilled` in last termination state.
- Datadog shows memory spike and restart event.

Commands:

```bash
kubectl -n scaleops-lab get pods
kubectl -n scaleops-lab describe pod <pod-name>
kubectl -n scaleops-lab get events --sort-by=.lastTimestamp
```

Diagnosis:

CPU can be throttled, but memory over the limit can kill the container. Memory sizing needs careful peak analysis.

Remediation options:

- Increase memory limit.
- Increase memory request if usage is sustained.
- Investigate memory leak or high allocation behavior.
- Add app-level memory controls.
- Avoid setting memory limits too close to normal operating peaks.

Interview narrative:

> The failure mode changed from slowness to restarts. That distinction matters. CPU pressure often creates latency, but memory limit pressure can terminate the container. I would inspect last termination state, restart count, and memory trends before changing resources.

Acceptance criteria:

- The user can intentionally cause an OOMKilled event.
- The runbook explains how to find the evidence.

---

## 20. Scenario F: Bad HPA signal

Path:

```text
k8s/overlays/bad-hpa-signal/
runbooks/bad-hpa-signal.md
```

Purpose:

Show that CPU-based autoscaling does not solve every slow-app problem.

Configuration:

- Add HPA based on CPU utilization.
- Set resource requests so HPA can calculate utilization.
- Generate latency using sleep or artificial dependency delay, not CPU.

Example HPA:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: synthetic-api
  namespace: scaleops-lab
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: synthetic-api
  minReplicas: 2
  maxReplicas: 8
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
```

Load test:

```bash
make load-test TEST=latency-spike
```

Expected behavior:

- Latency rises.
- CPU does not rise enough to trigger meaningful scaling.
- HPA does little or nothing.
- The service is slow even though autoscaling exists.

Diagnosis:

The scaling signal does not match the bottleneck. CPU-based HPA is useful when CPU is the constraining resource. It is not a universal latency fix.

Remediation options:

- Use application-level metrics if appropriate.
- Scale on request concurrency, queue depth, or latency-related metrics if reliable.
- Fix the dependency bottleneck.
- Add caching or timeouts.
- Avoid assuming more pods solve every slow request.

Interview narrative:

> The app was slow, but CPU was not the bottleneck. HPA did not help because it was watching the wrong signal. I would first identify whether the bottleneck is CPU, memory, network, dependency latency, queueing, or application lock contention before changing autoscaling policy.

Acceptance criteria:

- Latency increases without significant HPA response.
- User can explain why autoscaling did not solve the problem.

---

## 21. Scenario G: HPA works, but too late

Path:

```text
k8s/overlays/hpa-lag/
runbooks/hpa-lag.md
```

Purpose:

Show that autoscaling is reactive and may lag behind traffic spikes.

Configuration:

- HPA enabled on CPU.
- CPU request low enough for utilization to exceed target under load.
- App has a readiness delay so new pods take time before serving traffic.

Suggested environment variable:

```bash
READY_STARTUP_DELAY_SECONDS="15"
```

Load test:

```bash
make load-test TEST=ramp-cpu
```

Expected behavior:

- CPU rises.
- HPA increases desired replicas.
- New pods are created.
- New pods take time to become Ready.
- Latency may spike before stabilizing.

Diagnosis:

HPA is reactive. It needs metrics, scheduling time, image startup time, readiness success, and service routing before new capacity helps.

Remediation options:

- Increase minimum replicas for predictable traffic.
- Use scheduled or predictive scaling for known patterns.
- Reduce startup time.
- Improve readiness behavior.
- Scale earlier using better metrics.
- Tune HPA behavior carefully.

Interview narrative:

> HPA eventually helped, but it did not prevent the latency spike. That shows the difference between recovery and prevention. For predictable load, I would consider higher minimum replicas, scheduled scaling, faster startup, or better leading indicators.

Acceptance criteria:

- HPA desired replicas increases during the test.
- User can observe lag between load increase and stable recovery.

---

## 22. Scenario H: Bad probes

Path:

```text
k8s/overlays/bad-probes/
runbooks/bad-probes.md
```

Purpose:

Show how poorly designed liveness/readiness probes can create instability.

Configuration examples:

- Readiness probe points to an endpoint that sometimes fails.
- Liveness probe is too aggressive.
- Initial delay is too short for startup behavior.

Expected behavior:

- Pods flap Ready/NotReady.
- Service endpoints change frequently.
- Liveness failures may cause restarts.
- User-visible latency/errors may increase even though the app code is mostly fine.

Commands:

```bash
kubectl -n scaleops-lab describe pod <pod-name>
kubectl -n scaleops-lab get endpoints synthetic-api -w
kubectl -n scaleops-lab get events --sort-by=.lastTimestamp
```

Diagnosis:

Probe design is part of application reliability. Liveness answers “should Kubernetes restart this container?” Readiness answers “should this pod receive traffic?” Mixing those up can create self-inflicted outages.

Remediation options:

- Make liveness probe conservative.
- Make readiness probe reflect traffic-serving capability.
- Do not make liveness depend on fragile external dependencies.
- Add startup probes if needed.
- Tune thresholds and delays.

Interview narrative:

> The pod was not simply broken. Kubernetes was reacting to a bad health signal. I would treat probes as control-plane inputs, not just monitoring checks, because bad probes can actively destabilize a service.

Acceptance criteria:

- Probe failures are visible in `kubectl describe pod` and events.
- User can explain liveness vs readiness clearly.

---

## 23. Debug snapshot command

Implement:

```bash
make snapshot
```

This should collect a local debug bundle under:

```text
snapshots/<timestamp>/
```

Include:

```bash
kubectl get nodes -o wide
kubectl describe nodes
kubectl -n scaleops-lab get all -o wide
kubectl -n scaleops-lab describe deployments
kubectl -n scaleops-lab describe pods
kubectl -n scaleops-lab get events --sort-by=.lastTimestamp
kubectl -n scaleops-lab top pods
kubectl -n scaleops-lab top nodes
kubectl -n scaleops-lab logs deploy/synthetic-api --tail=200
kubectl -n scaleops-lab get hpa -o yaml
```

Commands that fail because a resource does not exist should not abort the whole snapshot.

Acceptance criteria:

- Snapshot command works during every scenario.
- Snapshot files are easy to inspect.
- Snapshot output is excluded from git by default.

---

## 24. Teaching documentation requirements

The documentation should teach Kubernetes through the lab, not as generic theory.

### `docs/00-learning-path.md`

Explain the recommended path:

1. Create cluster.
2. Deploy normal app.
3. Learn Pods, Deployments, and Services.
4. Learn requests and limits.
5. Trigger overprovisioning.
6. Trigger underprovisioning.
7. Trigger CPU throttling.
8. Trigger OOMKilled.
9. Add HPA.
10. Break HPA assumptions.
11. Break probes.
12. Build interview narrative.

### `docs/01-core-kubernetes-concepts.md`

Must explain:

- Container
- Pod
- ReplicaSet
- Deployment
- Service
- Namespace
- Node
- Control plane
- Desired state
- Reconciliation

Use this specific app as the example throughout.

### `docs/02-resource-requests-and-limits.md`

Must explain:

- CPU requests
- CPU limits
- Memory requests
- Memory limits
- Scheduling vs runtime usage
- QoS classes: Guaranteed, Burstable, BestEffort
- Why overprovisioning wastes capacity
- Why underprovisioning creates reliability risk

### `docs/03-scheduler-and-pending-pods.md`

Must explain:

- Why pods become Pending
- How to read pod events
- How requests influence scheduling
- Why a node can look idle but still reject a pod

### `docs/04-autoscaling.md`

Must explain:

- HPA
- Desired/current replicas
- CPU utilization target
- Metrics-server dependency
- Why HPA is reactive
- Why the scaling signal matters
- Difference between horizontal and vertical scaling

### `docs/05-probes.md`

Must explain:

- Liveness probe
- Readiness probe
- Startup probe
- Common probe mistakes
- Why probes are not just passive monitoring

### `docs/06-datadog-observability.md`

Must explain:

- What to look for in Datadog
- How to compare requested vs actual resources
- How to spot restarts and OOM kills
- How to spot CPU throttling
- How to interpret latency vs CPU
- How to use events with metric timelines

### `docs/07-interview-narrative.md`

Must give the user a concise interview story:

- What was built
- Why it was built
- What scenarios were tested
- What was learned
- How to approach “the site is slow”
- How to discuss tradeoffs

Include a reusable answer to:

> Walk me through how you would troubleshoot a slow Kubernetes-hosted web application.

---

## 25. Interview troubleshooting framework

The final docs should teach this exact diagnostic pattern:

```text
1. Clarify symptom
   Is it latency, errors, saturation, failed deploy, or unavailable service?

2. Scope blast radius
   One pod, one deployment, one node, one namespace, or whole cluster?

3. Check recent change
   Deployment, config, traffic, dependency, resource policy, node event?

4. Check app-level signals
   Request rate, latency, error rate, slow endpoints, logs, traces.

5. Check pod health
   Restarts, readiness, liveness, OOMKilled, image pulls, pending pods.

6. Check resource behavior
   CPU usage, memory usage, throttling, requests, limits.

7. Check scheduling and scaling
   Pending pods, HPA desired/current replicas, metrics availability.

8. Identify bottleneck
   CPU, memory, network, dependency, queue, lock contention, bad probe, or bad autoscaling signal.

9. Recommend tradeoff-aware fix
   More resources, better requests, fewer limits, more replicas, better metric, app fix, or dependency fix.

10. Validate outcome
   Compare before/after telemetry and ensure no new failure mode was introduced.
```

---

## 26. Implementation phases

### Phase 1: Local baseline

Deliverables:

- Repo structure.
- FastAPI synthetic app.
- Dockerfile.
- kind cluster config.
- Base Kubernetes manifests.
- Makefile commands for cluster, build, deploy, status, logs.
- Basic docs.

Acceptance criteria:

```bash
make check
make cluster-up
make build
make load-image
make deploy SCENARIO=normal
make status
make logs
```

All commands succeed.

### Phase 2: Load tests

Deliverables:

- k6 load scripts.
- Makefile load-test target.
- Port-forward or in-cluster job mode.

Acceptance criteria:

```bash
make load-test TEST=baseline
make load-test TEST=cpu-spike
make load-test TEST=memory-spike
```

All tests run and produce visible app impact.

### Phase 3: Failure scenarios

Deliverables:

- All Kustomize overlays.
- Runbooks for every scenario.
- Snapshot command.

Acceptance criteria:

Each of these works:

```bash
make deploy SCENARIO=overprovisioned
make deploy SCENARIO=underprovisioned
make deploy SCENARIO=cpu-throttling
make deploy SCENARIO=memory-pressure
make deploy SCENARIO=bad-hpa-signal
make deploy SCENARIO=hpa-lag
make deploy SCENARIO=bad-probes
make snapshot
```

### Phase 4: Datadog integration

Deliverables:

- Datadog Helm values.
- Datadog install script.
- Datadog dashboard guidance.
- Observability docs.

Acceptance criteria:

```bash
make install-datadog
```

Installs the agent when `.env` is configured.

### Phase 5: Interview polish

Deliverables:

- `docs/07-interview-narrative.md`
- Scenario summaries.
- Before/after observations.
- Troubleshooting framework.

Acceptance criteria:

The user can read the docs and explain:

- What a pod is.
- What a deployment is.
- What a service is.
- How requests differ from limits.
- Why pods become Pending.
- What CPU throttling means.
- Why memory pressure causes OOMKilled.
- Why HPA may not solve slow requests.
- How to reason through “the site is slow.”

---

## 27. Coding standards

Keep code simple.

Python:

- Use FastAPI.
- Keep dependencies minimal.
- Use clear function names.
- Add comments where behavior is intentionally synthetic.
- Log in structured JSON if practical.

Shell:

- Use `set -euo pipefail`.
- Print helpful errors.
- Do not assume `.env` exists.
- Do not destroy clusters without clear command names.

Kubernetes:

- Use Kustomize overlays.
- Keep base clean.
- Keep scenario-specific changes in overlays.
- Use labels consistently.
- Avoid unnecessary abstractions.

Docs:

- Write for a learner who knows containers but is new to Kubernetes.
- Prefer concrete lab examples over abstract explanations.
- Every scenario should answer: “What would I say in an interview?”

---

## 28. Safety and host protection

The lab intentionally creates CPU and memory pressure. Protect the user's machine.

Requirements:

- Keep load tests bounded.
- Do not run infinite CPU loops without timeout.
- Do not allocate unbounded memory.
- Do not create fork bombs or uncontrolled pod creation.
- HPA max replicas should be modest, for example `8`.
- Memory leak endpoint should have a maximum cap, configurable by environment variable.
- Load scripts should have clear duration limits.

Suggested app safeguards:

```bash
MAX_MEMORY_ALLOCATION_MB="512"
MAX_LEAK_MEMORY_MB="1024"
MAX_CPU_BURN_SECONDS="30"
```

Acceptance criteria:

- A bad test cannot accidentally consume the whole host indefinitely.
- Cleanup commands restore the cluster to normal or delete it.

---

## 29. Suggested README opening

The README should begin with something close to this:

```markdown
# ScaleOps Kubernetes Failure Lab

This project is a local Kubernetes learning lab designed for debugging and resource-optimization practice. It deploys a small synthetic API to a local kind cluster, then intentionally creates common Kubernetes failure modes: overprovisioning, underprovisioning, CPU throttling, memory pressure, bad autoscaling signals, autoscaling lag, and probe misconfiguration.

The goal is not just to run Kubernetes. The goal is to learn how Kubernetes symptoms appear in `kubectl`, cluster events, workload metrics, and Datadog, then practice explaining remediation tradeoffs clearly.
```

---

## 30. Final acceptance test

The project is complete when the following full flow works on a clean Linux machine with Docker installed:

```bash
git clone <repo>
cd scaleops-k8s-failure-lab
cp .env.example .env
# User optionally fills in DD_API_KEY and DD_SITE

make check
make cluster-up
make build
make load-image
make install-metrics-server
make deploy SCENARIO=normal
make load-test TEST=baseline
make snapshot

make deploy SCENARIO=overprovisioned
make snapshot

make deploy SCENARIO=underprovisioned
make load-test TEST=cpu-spike
make snapshot

make deploy SCENARIO=memory-pressure
make load-test TEST=memory-spike
make snapshot

make deploy SCENARIO=bad-hpa-signal
make load-test TEST=latency-spike
make snapshot

make deploy SCENARIO=hpa-lag
make load-test TEST=ramp-cpu
make snapshot

make deploy SCENARIO=bad-probes
make snapshot

make cluster-down
```

If Datadog credentials are configured, the user should also be able to run:

```bash
make install-datadog
```

And observe Kubernetes metrics, workload health, logs, and optionally traces in the Datadog sandbox.

---

## 31. The final user-facing success state

At the end of the project, the user should have:

1. A working local Kubernetes cluster.
2. A small synthetic API workload.
3. Repeatable load tests.
4. Repeatable failure scenarios.
5. Datadog visibility into the cluster and workload.
6. Scenario runbooks.
7. A debug snapshot workflow.
8. A clear interview narrative.

Most importantly, the user should be able to answer a ScaleOps-style scenario calmly:

> The site is slow. What do you check first, what signals matter, and how do you decide whether to change resources, change scaling, or investigate the application itself?
