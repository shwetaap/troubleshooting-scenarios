# Troubleshooting Scenarios

Reproducible OpenShift scenarios for AI-assisted troubleshooting. Each scenario deploys the environment and introduces a fault.

## Scenario suites

| Suite | Description |
|-------|-------------|
| [generic/](generic/) | General OpenShift fault-injection scenarios (database connection exhaustion, cascading alert storm). |
| [kiali-ossm/](kiali-ossm/) | Service-mesh troubleshooting scenarios using Kiali/OSSM MCP tools and OpenShift Lightspeed. |
| [netobserv/](netobserv/) | Network observability troubleshooting scenarios using the NetObserv MCP toolset and OpenShift Lightspeed. |

### generic

| Scenario | Description |
|----------|-------------|
| [01-payments-api-failure](generic/01-payments-api-failure/) | A routine rollout deploys a buggy version of the reporting service, which leaks database connections, exhausts a shared PostgreSQL pool, and causes payment failures in a separate namespace. |
| [02-alert-storm](generic/02-alert-storm/) | A misconfigured ConfigMap causes payments-api to fail, triggering a cascade of alerts across all dependent services. |

### kiali-ossm

Evaluation scenarios that test AI-assisted diagnosis of Istio/Kiali mesh problems. See [`kiali-ossm/README.md`](kiali-ossm/README.md) for setup instructions and a full description of each scenario.

### netobserv

Evaluation scenarios that test AI-assisted investigation of NetObserv network observability signals (DNS, packet drops, TLS, TCP RTT). See [`netobserv/README.md`](netobserv/README.md) for setup instructions and a full description of each scenario.

---

## Lightspeed evaluation setup

The `kiali-ossm` and `netobserv` scenarios are evaluated using [`lightspeed-evaluation`](https://github.com/lightspeed-core/lightspeed-evaluation), a framework that sends queries to an [OpenShift Lightspeed](https://github.com/openshift/lightspeed-service) (OLS) instance and scores responses with a judge LLM.

### Requirements

- Python 3.11, 3.12, or 3.13 (`lightspeed-evaluation` does not support 3.14+)
- A running OLS instance reachable from your machine — `https://localhost:8443` via port-forward, or the cluster Route (see eval suite README; operator listens on HTTPS **8443**, not 8080)
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

The MCP server gives OLS live access to the cluster through configurable toolsets (`core`, `config`, plus extras). Deploy from the repository root:

```bash
make setup-openshift-mcp
make connect-ols-mcp
```

For **Kiali/OSSM** evals the default toolset is `ossm`. For **NetObserv** evals, enable the `netobserv` toolset:

```bash
make setup-openshift-mcp TOOLSETS_ADDITIONAL=netobserv
make connect-ols-mcp
```

Both suites use the same Red Hat `openshift-mcp-server` image in the `openshift-mcp` namespace.

### 1. Deploy the MCP server

```bash
make setup-openshift-mcp
# or: make setup-openshift-mcp TOOLSETS_ADDITIONAL=netobserv
# or: make setup-openshift-mcp TOOLSETS_ADDITIONAL=ossm,netobserv
```

This:

1. Creates the `openshift-mcp` namespace
2. Creates a `ServiceAccount` and grants it `cluster-admin`
3. Builds and applies the `mcp-config` ConfigMap (see [Toolsets](#2-toolsets) below)
4. Deploys the MCP server pod
5. Creates a `Service` and exposes an OpenShift `Route`

The MCP server Route is printed at the end of the run.

#### Key variables

| Variable | Default | Description |
|---|---|---|
| `OPENSHIFT_MCP_NS` | `openshift-mcp` | Namespace for openshift-mcp-server |
| `OPENSHIFT_MCP_INTERNAL_IMAGE` | (fixed in Makefile) | Red Hat `openshift-mcp-server-rhel9` digest — not overridable |
| `OPENSHIFT_MCP_TOOLSETS` | `ossm` | Extra toolsets when `TOOLSETS_ADDITIONAL` is unset |
| `TOOLSETS_ADDITIONAL` | `ossm` | Comma-separated extra toolsets (`netobserv`, `ossm`, …) |

#### Testing upstream PRs (optional)

Before a toolset lands in `openshift-mcp-server`, you can deploy upstream [kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server) with a custom image in a separate namespace:

```bash
KUBERNETES_MCP_IMAGE=quay.io/<you>/kubernetes-mcp-server:<pr-tag> \
  make setup-kubernetes-mcp
make connect-ols-kubernetes-mcp
```

See `make help` for `kubernetes-mcp-config` and `teardown-kubernetes-mcp`. This path is for PR validation only — eval docs assume the openshift-mcp flow above.

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

To update configuration on a live deployment without a full reinstall:

```bash
make mcp-config TOOLSETS_ADDITIONAL=ossm,mytoolset
```

(`make mcp-config` is an alias for `openshift-mcp-config`.)

### 3. Connect OLS to the MCP server

Once the MCP server is running, register it with OpenShift Lightspeed:

```bash
make connect-ols-mcp
```

This patches `OLSConfig/cluster` to add the MCP server under `spec.mcpServers`, then restarts `lightspeed-app-server`:

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

```bash
make teardown-openshift-mcp
```

This:

1. Removes `spec.mcpServers` from `OLSConfig/cluster`
2. Restarts `lightspeed-app-server`
3. Deletes Deployment, Service, Route, ConfigMap, ClusterRoleBinding, ServiceAccount in the flavor namespace
4. Deletes the `openshift-mcp` namespace

All steps are idempotent.

### 5. Other lifecycle targets

```bash
make mcp-config              # rebuild config and restart pod
make setup-kubernetes-mcp    # optional: upstream image for PR testing
```
