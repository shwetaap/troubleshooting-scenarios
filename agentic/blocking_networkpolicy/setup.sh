#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="service-mesh"

echo "Applying blocking_networkpolicy scenario manifests in namespace ${NS}…"
oc apply -f "$FIXTURE_DIR/manifest.yaml"

echo "Waiting for backend deployment to be ready…"
oc wait --for=condition=available deployment/backend -n "$NS" --timeout=60s

echo "Waiting for frontend to report connection timeout (up to 90s)…"
ATTEMPT=0
until [ "$ATTEMPT" -ge 30 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  if oc logs -l app=frontend -n "$NS" --tail=20 2>/dev/null \
     | grep -q "ERROR: Connection timeout to backend-service!"; then
    echo "Scenario blocking_networkpolicy ready — frontend→backend timeout confirmed (attempt ${ATTEMPT})"
    exit 0
  fi
  echo "  attempt ${ATTEMPT}/30 — waiting 3s…"
  sleep 3
done

echo "ERROR: Connection timeout error not found within 90s"
oc get pods -n "$NS"
oc logs -l app=frontend -n "$NS" --tail=10 2>/dev/null || true
exit 1
