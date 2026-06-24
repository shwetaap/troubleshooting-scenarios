# NetObserv Troubleshooting Evaluation Scenarios

Evaluation scenarios that test how well an AI assistant — backed by the OpenShift MCP server with the NetObserv toolset and OpenShift Lightspeed — can investigate network observability problems on a live OpenShift cluster.

## Prerequisites

- OpenShift cluster accessible via `oc login`
- `OPENAI_API_KEY` exported

## Quick start

```bash
export OPENAI_API_KEY=<your-key>
make setup     # install venv + OLS + MCP (netobserv toolset) + NetObserv operator + FlowCollector
make evals     # run all scenarios
make cleanup  # remove NetObserv + MCP
```

`make setup` handles everything: venv creation, OLS operator install, MCP server deployment with the `netobserv` toolset, and NetObserv operator + FlowCollector installation via [`build/netobserv.mk`](build/netobserv.mk). See [`build/README.md`](build/README.md) for details on NetObserv variables and manual steps.

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

Applications report slow DNS lookups. The agent must use NetObserv flow metrics or flow logs to identify affected workloads.

```bash
make dns_latency-eval
```

### `dns_nxdomain`

DNS resolution failures in `netobserv-eval-dns-nxdomain`. The agent must find NXDOMAIN evidence in flow metrics and/or flow logs.

```bash
make dns_nxdomain-eval
```

### `packet_drops_kernel`

Kernel-level packet drops in `netobserv-eval-drops-kernel`. The agent must distinguish kernel drops from policy drops using NetObserv flow data.

```bash
make packet_drops_kernel-eval
```

### `packet_drops_policy`

NetworkPolicy blocking traffic in `netobserv-eval-drops-policy`. The agent must find policy-related drops (`OVS_DROP_EXPLICIT`, `packetLoss=dropped`) between workloads.

```bash
make packet_drops_policy-eval
```

### `tls_issues`

HTTPS/TLS connection problems in `netobserv-eval-tls`. The agent must investigate failed connections and TLS-related flow evidence.

```bash
make tls_issues-eval
```

### `tcp_rtt`

High TCP round-trip time in `netobserv-eval-tcp-rtt`. The agent must cite elevated RTT in flow metrics and `TimeFlowRttNs` in flows.

```bash
make tcp_rtt-eval
```

## Running all scenarios

```bash
export OPENAI_API_KEY=<your-key>
make evals
```

Results are written to `results/`.

To use a cluster Route instead of auto port-forward:

```bash
OLS_URL=https://<ols-route-host> make evals
```

## Evaluation framework

Scenarios are scored by a judge LLM (configured in [`system.yaml`](system.yaml)) using the `custom:answer_correctness` metric per turn. The framework is [`lightspeed-eval`](https://github.com/lightspeed-core/lightspeed-evaluation).
