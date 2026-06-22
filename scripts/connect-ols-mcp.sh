#!/usr/bin/env bash
set -euo pipefail

OLS_NS="${OLS_NS:-openshift-lightspeed}"
MCP_NS="${MCP_NS:-openshift-mcp}"
MCP_DEPLOYMENT="${MCP_DEPLOYMENT:-openshift-mcp-server}"
MCP_OLS_NAME="${MCP_OLS_NAME:-openshift-mcp}"

MCP_URL="http://${MCP_DEPLOYMENT}.${MCP_NS}:8080/mcp"

echo "==> Registering MCP server in OLSConfig (name=${MCP_OLS_NAME}, url=${MCP_URL})..."

patch="$(printf \
  '{"spec":{"featureGates":["MCPServer"],"mcpServers":[{"name":"%s","headers":[{"name":"kubernetes-authorization","valueFrom":{"type":"kubernetes"}}],"url":"%s","timeout":120}]}}' \
  "$MCP_OLS_NAME" "$MCP_URL")"

oc patch olsconfig cluster --type=merge -p "$patch"

echo "==> Restarting lightspeed-app-server..."
oc rollout restart deployment/lightspeed-app-server -n "$OLS_NS"
oc rollout status deployment/lightspeed-app-server -n "$OLS_NS" --timeout=300s

# Poll HTTP endpoint until OLS is serving
OLS_PORT="${OLS_PORT:-8443}"
echo "==> Waiting for OLS to respond..."
for i in $(seq 1 30); do
  if oc exec -n "$OLS_NS" deployment/lightspeed-app-server -- \
    curl -ksf --connect-timeout 3 "https://localhost:8443/docs" >/dev/null 2>&1; then
    echo "==> OLS connected to MCP and ready."
    exit 0
  fi
  sleep 2
done

echo "WARN: OLS pod ready but /docs endpoint not responding after 60s — may still be starting"
