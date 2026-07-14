#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="platform-core"

echo "Applying mismatched_ingress_rule scenario manifests in namespace ${NS}…"
oc apply -f "$FIXTURE_DIR/api-gateway.yaml"

echo "Waiting for api-gateway deployment to be ready…"
oc wait --for=condition=available deployment/api-gateway -n "$NS" --timeout=60s

oc apply -f "$FIXTURE_DIR/web-portal.yaml"

echo "Waiting for web-portal to report connection timeout (up to 60s)…"
ATTEMPT=0
until [ "$ATTEMPT" -ge 30 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  if oc logs -l app=web-portal -n "$NS" --tail=20 2>/dev/null \
     | grep -q "ERROR: Connection timeout to api-gateway-svc!"; then
    echo "Scenario mismatched_ingress_rule ready — timeout error detected (attempt ${ATTEMPT})"
    exit 0
  fi
  [ $((ATTEMPT % 10)) -eq 0 ] && echo "  attempt ${ATTEMPT}/30 — waiting…"
  sleep 2
done

echo "ERROR: Connection timeout error not found within 60s"
oc get pods -n "$NS"
oc logs -l app=web-portal -n "$NS" --tail=10 2>/dev/null || true
exit 1
