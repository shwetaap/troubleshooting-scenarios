# NetObserv Troubleshooting Evaluation Scenarios

Evaluation scenarios that test how well an AI assistant — backed by the OpenShift MCP server with the NetObserv toolset and OpenShift Lightspeed — can investigate network observability problems on a live OpenShift cluster.

---

## Prerequisites

### 1. Cluster login and NetObserv

You must be logged in to a running OpenShift cluster with NetObserv installed (`FlowCollector` named `cluster`, Ready).

```bash
oc login <cluster-api-url>
oc get flowcollector cluster
```

If NetObserv is not installed yet, follow [`build/README.md`](build/README.md).

### 2. MCP server with NetObserv toolset

Same path as [kiali-ossm](../kiali-ossm/README.md): deploy **openshift-mcp-server** from the repository root with the `netobserv` toolset enabled:

```bash
make setup-openshift-mcp TOOLSETS_ADDITIONAL=netobserv
make connect-ols-mcp
```

See the root [README](../README.md#openshift-mcp-server-setup). To test an upstream PR before the toolset ships in openshift-mcp-server, use `make setup-kubernetes-mcp` with `KUBERNETES_MCP_IMAGE` — see [`build/README.md`](build/README.md).

### 3. OpenShift Lightspeed (OLS)

Evals call OLS `/v1/query`. The operator serves **HTTPS on port 8443** inside the pod (`lightspeed-service-api`, container port `https`) — not HTTP on 8080.

**Option A — cluster Route** (simplest, no port-forward):

```bash
export OPENAI_API_KEY=<your-key>
OLS_URL=$(make -s ols-route-url) make dns_nxdomain-test
```

**Option B — port-forward** to localhost:

Terminal 1:

```bash
make ols-port-forward
# oc port-forward -n openshift-lightspeed deployment/lightspeed-app-server 8443:8443
```

Terminal 2:

```bash
export OPENAI_API_KEY=<your-key>
make dns_nxdomain-test   # default OLS_URL=https://localhost:8443
```

See [openshift/lightspeed-service](https://github.com/openshift/lightspeed-service) for operator install and `OLSConfig`.

---

## Scenarios

Each scenario deploys synthetic traffic, waits for NetObserv export, asks OLS to investigate, and scores the response. Scenarios with a `setup_script` in [`evals.yaml`](evals.yaml) deploy workloads before the conversation and clean up afterwards.

| Tag | Category | Description |
|-----|----------|-------------|
| `dns_latency` | DNS | Slow DNS lookups — flow metrics and `DnsLatencyMs` |
| `dns_nxdomain` | DNS | DNS failures / NXDOMAIN — `DnsFlagsResponseCode`, flow DNS fields |
| `packet_drops_kernel` | Drops | Kernel packet drops — `PktDrop*` flow fields |
| `packet_drops_policy` | Drops | NetworkPolicy denials — `OVS_DROP_EXPLICIT`, policy drop flows |
| `tls_issues` | Ingress/TLS | HTTPS/TLS errors — failed connections on port 443 |
| `tcp_rtt` | Latency | Slow TCP RTT — `TimeFlowRttNs` and RTT flow metrics |

Setup scripts wait for workload traffic, then **`wait_for_netobserv_warmup`** (default **120s**) so flows reach Loki before OLS is queried. Override with `NETOBSERV_WARMUP_SECS=180` on slow clusters.

### `dns_latency`

**Tag:** `dns_latency`

Applications report slow DNS lookups. The agent must use NetObserv flow metrics or flow logs to identify affected workloads.

```bash
make dns_latency-test
```

### `dns_nxdomain`

**Tag:** `dns_nxdomain`

DNS resolution failures in `netobserv-eval-dns-nxdomain`. The agent must find NXDOMAIN evidence in flow metrics and/or flow logs.

```bash
make dns_nxdomain-test
```

### `packet_drops_kernel`

**Tag:** `packet_drops_kernel`

Kernel-level packet drops in `netobserv-eval-drops-kernel`. The agent must distinguish kernel drops from policy drops using NetObserv flow data.

```bash
make packet_drops_kernel-test
```

### `packet_drops_policy`

**Tag:** `packet_drops_policy`

NetworkPolicy blocking traffic in `netobserv-eval-drops-policy`. The agent must find policy-related drops (`OVS_DROP_EXPLICIT`, `packetLoss=dropped`) between workloads.

```bash
make packet_drops_policy-test
```

### `tls_issues`

**Tag:** `tls_issues`

HTTPS/TLS connection problems in `netobserv-eval-tls`. The agent must investigate failed connections and TLS-related flow evidence.

```bash
make tls_issues-test
```

### `tcp_rtt`

**Tag:** `tcp_rtt`

High TCP round-trip time in `netobserv-eval-tcp-rtt`. The agent must cite elevated RTT in flow metrics and `TimeFlowRttNs` in flows.

```bash
make tcp_rtt-test
```

---

## Running all scenarios

From the **repository root**, install the evaluation CLI once (creates `venv/` with `lightspeed-eval`):

```bash
make setup-ols-evaluation
```

The judge LLM requires an OpenAI API key. Export it before running any test target:

```bash
export OPENAI_API_KEY=<your-key>
```

Then run scenarios from this directory (with OLS reachable — see [Prerequisites §3](README.md#3-openshift-lightspeed-ols)):

```bash
make test              # all scenarios
make dns_latency-test  # single scenario
```

Results are written to `results/`.

---

## Evaluation framework

Scenarios are scored by a judge LLM (configured in [`system.yaml`](system.yaml)) using the `custom:answer_correctness` metric per turn. The framework is [`lightspeed-eval`](https://github.com/lightspeed-core/lightspeed-evaluation); install it with `make setup-ols-evaluation` from the repository root (see [`Makefile`](../Makefile)).
