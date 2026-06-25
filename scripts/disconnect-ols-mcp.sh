#!/usr/bin/env bash
set -euo pipefail

OLS_NS="${OLS_NS:-openshift-lightspeed}"

echo "==> Removing MCP servers from OLSConfig..."
oc patch olsconfig cluster --type=json \
  -p='[{"op":"remove","path":"/spec/mcpServers"}]' 2>/dev/null || true

echo "==> Restarting lightspeed-app-server..."
oc rollout restart deployment/lightspeed-app-server -n "$OLS_NS" 2>/dev/null || true
oc rollout status deployment/lightspeed-app-server -n "$OLS_NS" --timeout=300s 2>/dev/null || true

echo "==> OLS disconnected from MCP."
