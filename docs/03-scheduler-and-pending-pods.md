# Scheduler And Pending Pods

Pods become Pending when Kubernetes cannot place them on a node. Common reasons include insufficient requested CPU, insufficient requested memory, taints, node selectors, or image issues.

For this lab, `overprovisioned` is the key case. The pod can be Pending even if `kubectl top nodes` shows low actual CPU because the scheduler is protecting requested capacity.

Useful commands:

```bash
kubectl -n scaleops-lab get pods -o wide
kubectl -n scaleops-lab describe pod <pod>
kubectl describe node <node>
kubectl -n scaleops-lab get events --sort-by=.lastTimestamp
```

Interview line: "The node was not necessarily busy at runtime; it lacked schedulable capacity because requests were too high."

