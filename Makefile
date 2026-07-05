SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
export PATH := $(HOME)/.local/bin:$(PATH)

SCENARIO ?= normal
TEST ?= baseline

.PHONY: help check cluster-up cluster-down build load-image install-metrics-server install-datadog deploy status logs load-test snapshot clean

help:
	@echo "ScaleOps Kubernetes Failure Lab"
	@echo
	@echo "Targets:"
	@echo "  make check"
	@echo "  make cluster-up"
	@echo "  make cluster-down"
	@echo "  make build"
	@echo "  make load-image"
	@echo "  make install-metrics-server"
	@echo "  make install-datadog"
	@echo "  make deploy SCENARIO=normal"
	@echo "  make status"
	@echo "  make logs"
	@echo "  make load-test TEST=baseline"
	@echo "  make snapshot"
	@echo "  make clean"

check:
	@echo "Concept: A repeatable lab starts with explicit local tool checks."
	@scripts/check-prereqs.sh

cluster-up:
	@echo "Concept: kind creates disposable Kubernetes nodes as local Docker containers."
	@scripts/create-cluster.sh

cluster-down:
	@echo "Concept: Local clusters should be easy to destroy so failure experiments stay low-risk."
	@scripts/delete-cluster.sh

build:
	@echo "Concept: Kubernetes runs container images; this builds the synthetic API image."
	@scripts/build-image.sh

load-image:
	@echo "Concept: kind nodes need the image loaded into the cluster-local container runtime."
	@scripts/load-image.sh

install-metrics-server:
	@echo "Concept: HPA and kubectl top depend on resource metrics from metrics-server."
	@scripts/install-metrics-server.sh

install-datadog:
	@echo "Concept: Datadog correlates Kubernetes state, resource pressure, logs, and events."
	@scripts/install-datadog.sh

deploy:
	@echo "Concept: Scenario overlays change requests, limits, probes, or autoscaling behavior."
	@echo "Deploying scenario: $(SCENARIO)"
	@scripts/deploy-scenario.sh "$(SCENARIO)"

status:
	@echo "Concept: Start diagnosis with desired state, pod health, events, and scaling state."
	@kubectl -n $${NAMESPACE:-scaleops-lab} get deploy,rs,pods,svc,hpa -o wide 2>/dev/null || true
	@kubectl -n $${NAMESPACE:-scaleops-lab} get events --sort-by=.lastTimestamp | tail -30 2>/dev/null || true

logs:
	@echo "Concept: App logs connect Kubernetes symptoms to request-level behavior."
	@kubectl -n $${NAMESPACE:-scaleops-lab} logs deploy/synthetic-api --tail=100 -f

load-test:
	@echo "Concept: Bounded load makes resource symptoms observable and repeatable."
	@echo "Running load test: $(TEST)"
	@scripts/run-load.sh "$(TEST)"

snapshot:
	@echo "Concept: A debug bundle preserves the evidence before remediation changes the system."
	@scripts/collect-debug-snapshot.sh

clean:
	@echo "Concept: Reset local artifacts without hiding Kubernetes cleanup from the learner."
	@rm -rf snapshots
