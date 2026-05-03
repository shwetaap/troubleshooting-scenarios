# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This repository contains reproducible OpenShift troubleshooting demo scenarios for teaching AI-assisted incident response. Each scenario deploys a realistic microservice environment, introduces a fault, and requires an AI assistant to diagnose the root cause.

## Repository Structure

Each top-level directory is an independent scenario with its own Makefile, manifests, application code, and scripts.

## Working with Scenarios

All commands run from within a scenario directory (e.g., `cd 01-payments-api-failure/`).

### Prerequisites

- `oc login` to an OpenShift 4.x cluster

### Lifecycle Commands (via Make)

Each scenario exposes a common set of Make targets. Not all targets exist in every scenario.

```bash
make deploy          # Deploy healthy state
make break           # Introduce the fault, wait for failure + alert
make fix             # Roll back to healthy state
make cleanup         # Delete all demo resources
make delete-history  # Reset Prometheus TSDB and restart pods
make update-images     # Rebuild and push container images to Quay.io
```

Scenario-specific targets (01-payments-api-failure only):

```bash
make deploy-easy       # Deploy with per-service DB users (easier diagnosis)
make break-redherring  # Add a red herring (CrashLoopBackOff)
make fix-redherring    # Remove the red herring
make break-network     # Block egress from payments-api via NetworkPolicy
make fix-network       # Remove the deny-all-egress NetworkPolicy
```

## Architecture: 01-payments-api-failure (Database Connection Exhaustion)

Two OpenShift namespaces share a PostgreSQL database with `max_connections=20`:

- **`payments`** namespace: `payments-api` (Python/FastAPI) serves `GET /api/v1/process-payment` and runs a background traffic simulator. Connects cross-namespace to `postgres.shared-services.svc.cluster.local`.
- **`shared-services`** namespace: `postgres` (with postgres-exporter sidecar on port 9187), `reporting-service` (two versions), and `reconciliation-service` (intentional red herring, always in CrashLoopBackOff).

The fault: `reporting-service` v1.0.2 accumulates database connections without closing them, exhausting the shared pool and causing payments-api to return 503s from a different namespace.

Monitoring is wired via Prometheus ServiceMonitors and PrometheusRules with alerts on error rate (`PaymentErrorRateHigh`) and connection count (`PostgresqlConnectionsHigh`, `PostgresqlTooManyConnections`).

### Key Paths

- `01-payments-api-failure/CLAUDE.md` -- context given to the AI assistant performing the investigation (not a dev guide)
- `01-payments-api-failure/manifests/payments/` -- Kubernetes manifests for the payments namespace
- `01-payments-api-failure/manifests/shared-services/` -- Kubernetes manifests for the shared-services namespace
- `01-payments-api-failure/scripts/` -- shell scripts that implement each Make target
- `01-payments-api-failure/reporting-service/v1.0.1/` -- healthy version
- `01-payments-api-failure/reporting-service/v1.0.2/` -- buggy version (connection leak + division by zero)

## Architecture: 02-alert-storm (Cascading Alert Storm)

Single `payments` namespace with five microservices:

- **`payments-api`**: Central service that processes payments. Loads config from a mounted ConfigMap.
- **`checkout-service`**, **`order-processor`**, **`refund-service`**, **`notification-service`**: Downstream services that depend on `payments-api` via HTTP.

The fault: A broken ConfigMap is applied to `payments-api`, causing it to fail. All four downstream services degrade in cascade, triggering a storm of alerts that obscures the simple root cause.

Monitoring is wired via Prometheus ServiceMonitors and PrometheusRules with alerts on error rates, latency, queue depths, and resource usage across all five services.

### Key Paths

- `02-alert-storm/CLAUDE.md` -- context given to the AI assistant performing the investigation
- `02-alert-storm/manifests/` -- Kubernetes manifests (namespace, deployments, ServiceMonitors, PrometheusRules)
- `02-alert-storm/manifests/configmaps/` -- healthy and broken ConfigMap variants
- `02-alert-storm/scripts/` -- shell scripts that implement each Make target
- `02-alert-storm/images/` -- Dockerfiles and Python source for all five services

## Tech Stack

- **Applications**: Python 3.12, FastAPI (all services), raw psycopg2 (01 reporting-service)
- **Infrastructure**: OpenShift 4.x, PostgreSQL 16, Prometheus user workload monitoring
- **Container images**: Built with Dockerfile, hosted on Quay.io
- **Deployment**: Raw Kubernetes YAML manifests applied via `oc apply`, no Helm/Kustomize
