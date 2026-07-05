# Core Kubernetes Concepts

A container is the packaged `synthetic-api` process. A Pod is Kubernetes' smallest schedulable unit; here each pod runs one API container. A ReplicaSet keeps the requested number of pods alive, and a Deployment manages ReplicaSets during rollouts. The Service named `synthetic-api` gives stable networking to whichever pods are Ready.

The Namespace `scaleops-lab` keeps lab resources grouped. Nodes are the kind worker containers that run pods. The control plane stores desired state and runs controllers. Reconciliation is the loop where Kubernetes compares desired state, such as two replicas, with actual state, such as one crashed pod, then acts to close the gap.

In this lab, every scenario changes desired state. Kubernetes then shows you the consequence: scheduling, restarts, readiness, or scaling.

