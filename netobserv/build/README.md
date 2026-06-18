# NetObserv Prerequisites

NetObserv evaluation scenarios assume a live OpenShift cluster with the Network Observability operator installed and a `FlowCollector` resource named `cluster` in Ready state.

## Cluster login

```bash
oc login <cluster-api-url>
oc get flowcollector cluster -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
```

## NetObserv operator

Install the operator and Loki from the upstream [netobserv-operator](https://github.com/netobserv/netobserv-operator) repository ([`deploy` target](https://github.com/netobserv/netobserv-operator/blob/main/Makefile#L417)):

```bash
USER=netobserv make deploy deploy-loki
```

Do **not** use `make deploy-sample-cr` — its defaults are unsuitable for evals (sampling 50, no eBPF features, non-privileged agent, network policy blocks the MCP server).

Apply the eval `FlowCollector` from this repository instead:

```bash
oc apply -f build/flowcollector.yaml
oc wait flowcollector/cluster --for=condition=Ready --timeout=10m
```

Or from `netobserv/`:

```bash
make deploy-flowcollector
```

| Setting | Sample CR | Eval `flowcollector.yaml` |
|---------|-----------|---------------------------|
| `sampling` | 50 | 1 |
| `privileged` | false | true |
| eBPF features | commented out | DNSTracking, PacketDrop, FlowRTT, NetworkEvents |
| `networkPolicy.additionalNamespaces` | `[]` | `openshift-mcp` |

`NetworkEvents` requires OpenShift 4.19+. All scenarios and their required features:

| Scenario | FlowCollector eBPF feature |
|----------|---------------------------|
| `dns_latency`, `dns_nxdomain` | `DNSTracking` |
| `packet_drops_kernel` | `PacketDrop` |
| `packet_drops_policy` | `NetworkEvents` |
| `tls_issues` | `NetworkEvents` |
| `tcp_rtt` | `FlowRTT` |

## MCP server

Eval scenarios use the **netobserv** toolset on **openshift-mcp-server** (same as kiali-ossm uses `ossm`). From the **repository root**:

```bash
make setup-openshift-mcp TOOLSETS_ADDITIONAL=netobserv
make connect-ols-mcp
```

### Testing upstream PRs (optional)

Before the NetObserv toolset lands in openshift-mcp-server, deploy upstream [kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server) with a custom image:

```bash
KUBERNETES_MCP_IMAGE=quay.io/<you>/kubernetes-mcp-server:<pr-tag> \
  make setup-kubernetes-mcp
make connect-ols-kubernetes-mcp
```

Update `flowcollector.yaml` `networkPolicy.additionalNamespaces` to `kubernetes-mcp-server` if you use this path. Teardown: `make teardown-kubernetes-mcp`.

See the root [README](../../README.md#openshift-mcp-server-setup) for the full MCP lifecycle.
