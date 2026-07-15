# Agentic Evals

Behavioral evals for automated troubleshooting with [OpenShift Agentic Lightspeed](https://github.com/openshift/lightspeed-agentic-operator). Each scenario deploys a fault on a live cluster, submits a configurable number of `AgenticRun`s and scores the analysis.

## Scenarios

| Suite | Symptom | Root Cause |
|-------|---------|------------|
| `blocking_networkpolicy` | Frontend gets connection timeouts to backend | NetworkPolicy only allows ingress from `tier=backend`, blocking `tier=frontend` pods |
| `failing_api` | Payment API returning 503s (100% error rate) | Reporting service leaks DB connections, exhausting the shared PostgreSQL pool |
| `misconfigured_readiness_probe` | Pod running but not becoming Ready | HTTP readiness probe targets port 9200 but container has no HTTP server |
| `mismatched_ingress_rule` | Web-portal gets connection timeouts to API gateway | NetworkPolicy ingress rule label selector does not match the caller's labels |
| `missing_envvar` | Pod in CrashLoopBackOff | Required environment variable `DEPLOY_ENV` is missing from the deployment spec |
| `pending_pvc` | PVC stuck in Pending, pods cannot start | PVC references a StorageClass (`standard-v2`) that does not exist |
| `scheduled_outage` | Upstream timeouts during 03:00-03:05 window | Upstream API has a scheduled maintenance window, not a bug in the application |
| `batch_failure` | inventory-sync-validator Job fails | Job cannot connect to database at prod-db:3333 (connection refused) |

## Prerequisites

- `oc login` to an OpenShift 5.x cluster
- `OPENAI_API_KEY` exported
- [lightspeed-agentic-operator](https://github.com/openshift/lightspeed-agentic-operator) installed

## Usage

All commands run from this directory.

```bash
make setup                  # Install Python venv
make evals                  # Run all scenarios
make evals SUITES="failing_api pending_pvc"  # Run specific scenarios
make evals RUNS=3           # Run each scenario 3 times
make cleanup                # Remove scenario resources and venv
make help                   # Show all targets and options
```
