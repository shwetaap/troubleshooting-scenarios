#!/usr/bin/env bash
set -euo pipefail

MCP_NS="${MCP_NS:-openshift-mcp}"
MCP_DEPLOYMENT="${MCP_DEPLOYMENT:-openshift-mcp-server}"

echo "==> Removing MCP resources from ${MCP_NS}..."
oc delete deployment  "$MCP_DEPLOYMENT" -n "$MCP_NS" --ignore-not-found
oc delete service     "$MCP_DEPLOYMENT" -n "$MCP_NS" --ignore-not-found
oc delete configmap   mcp-config        -n "$MCP_NS" --ignore-not-found
oc delete clusterrolebinding "${MCP_DEPLOYMENT}-admin" --ignore-not-found
oc delete serviceaccount "$MCP_DEPLOYMENT" -n "$MCP_NS" --ignore-not-found
oc delete namespace "$MCP_NS" --ignore-not-found
echo "==> MCP cleanup complete (${MCP_NS})."
