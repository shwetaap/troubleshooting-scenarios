# Troubleshooting Scenarios

Reproducible OpenShift scenarios for AI-assisted troubleshooting. Each scenario deploys the environment and introduces a fault.

## Scenario suites

| Suite | Description |
|-------|-------------|
| [generic/](generic/) | General OpenShift fault-injection scenarios (database connection exhaustion, cascading alert storm). |
| [kiali-ossm/](kiali-ossm/) | Service-mesh troubleshooting scenarios using Kiali/OSSM MCP tools and OpenShift Lightspeed. |

### generic

| Scenario | Description |
|----------|-------------|
| [01-payments-api-failure](generic/01-payments-api-failure/) | A routine rollout deploys a buggy version of the reporting service, which leaks database connections, exhausts a shared PostgreSQL pool, and causes payment failures in a separate namespace. |
| [02-alert-storm](generic/02-alert-storm/) | A misconfigured ConfigMap causes payments-api to fail, triggering a cascade of alerts across all dependent services. |

### kiali-ossm

Evaluation scenarios that test AI-assisted diagnosis of Istio/Kiali mesh problems. See [`kiali-ossm/README.md`](kiali-ossm/README.md) for setup instructions and a full description of each scenario.

---

## Lightspeed evaluation setup

The `kiali-ossm` scenarios are evaluated using [`lightspeed-evaluation`](https://github.com/lightspeed-core/lightspeed-evaluation), a framework that sends queries to an [OpenShift Lightspeed](https://github.com/openshift/lightspeed-service) (OLS) instance and scores responses with a judge LLM.

### Requirements

- Python 3.11, 3.12, or 3.13 (`lightspeed-evaluation` does not support 3.14+)
- A running OLS instance reachable from your machine (configure `api.api_base` in `kiali-ossm/system.yaml`)
- `OPENAI_API_KEY` exported in your shell (used by the judge LLM)
- An OpenShift cluster accessible via `oc`

### Install evaluation framework

From the repository root, create a virtualenv and install the evaluation framework:

```bash
make setup-ols-evaluation
```

This creates `./venv` and installs `lightspeed-evaluation` directly from the `lightspeed-core` GitHub repository. You only need to run this once (or after deleting the venv).

---

## OpenShift MCP Server setup

The MCP server gives OLS live access to the cluster through a set of configurable toolsets. The following Make targets manage its full lifecycle from the repository root.

### 1. Deploy the MCP server

```bash
make setup-openshift-mcp
```

This single command:

1. Creates the `openshift-mcp` namespace
2. Creates a `ServiceAccount` and grants it `cluster-admin`
3. Builds and applies the `mcp-config` ConfigMap (see [Toolsets](#2-toolsets) below)
4. Deploys the MCP server pod
5. Creates a `Service` and exposes an OpenShift `Route`

The MCP server endpoint is printed at the end of the run.

#### Key variables

| Variable | Default | Description |
|---|---|---|
| `MCP_NS` | `openshift-mcp` | Namespace where the MCP server is deployed |
| `MCP_IMAGE_TAG` | `latest` | Tag for the MCP server image |
| `TOOLSETS_ADDITIONAL` | `ossm` | Extra toolsets to enable (comma-separated) |

### 2. Toolsets

The MCP server is configured with a base set of toolsets (`core`, `config`) plus any extras listed in `TOOLSETS_ADDITIONAL`. The value is a comma-separated list of toolset names:

```bash
# Default
make setup-openshift-mcp

# Add multiple toolsets
make setup-openshift-mcp TOOLSETS_ADDITIONAL=ossm,mytoolset

# No extra toolsets — base only
make setup-openshift-mcp TOOLSETS_ADDITIONAL=
```

When `ossm` is included, a `[toolset_configs.kiali]` section is automatically appended to `config.toml`:

```toml
toolsets = ["core","config","ossm"]
log_level = 0
port = "8080"
read_only = false

[toolset_configs.kiali]
url = "https://kiali.istio-system:20001/"
insecure = true
```

To update the configuration on a live deployment without a full reinstall:

```bash
make mcp-config                                       # rebuild ConfigMap and restart the pod
make mcp-config TOOLSETS_ADDITIONAL=ossm,mytoolset    # change toolsets on the fly
```

### 3. Connect OLS to the MCP server

Once the MCP server is running, register it with OpenShift Lightspeed by patching `OLSConfig/cluster`:

```bash
make connect-ols-mcp
```

This patches `OLSConfig/cluster` to add the MCP server under `spec.mcpServers`, then restarts `lightspeed-app-server` so OLS picks up the new configuration:

```yaml
spec:
  mcpServers:
  - name: openshift-mcp
    headers:
    - name: kubernetes-authorization
      valueFrom:
        type: kubernetes
    url: 'http://openshift-mcp-server.openshift-mcp:8080/mcp'
    timeout: 30
```

The `OLS_NS` variable controls which namespace OLS is installed in (default: `openshift-lightspeed`).

### 4. Teardown

To remove the MCP server completely and disconnect it from OLS:

```bash
make teardown-openshift-mcp
```

This performs a full cleanup in order:

1. Removes `spec.mcpServers` from `OLSConfig/cluster` so OLS stops routing to the MCP server
2. Restarts `lightspeed-app-server` to apply the disconnection
3. Deletes all cluster resources in `openshift-mcp`: Deployment, Service, Route, ConfigMap, ClusterRoleBinding, ServiceAccount
4. Deletes the `openshift-mcp` namespace

All steps are idempotent — safe to run even on a partially cleaned state.

### 5. Other lifecycle targets

```bash
make mcp-config              # rebuild config and restart pod (live reconfiguration)
```
