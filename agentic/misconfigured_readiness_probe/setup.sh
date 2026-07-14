#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="discovery-hub"
POD_NAME="catalog-index-service"

echo "Applying misconfigured_readiness_probe scenario manifests in namespace ${NS}…"
oc apply -f "$FIXTURE_DIR/manifest.yaml"

echo "Waiting for readiness probe failure event (up to 60s)…"
ATTEMPT=0
until [ "$ATTEMPT" -ge 60 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  EVENTS=$(oc get events -n "$NS" \
    --field-selector "involvedObject.name=$POD_NAME,reason=Unhealthy" \
    -o jsonpath='{.items[*].message}' 2>/dev/null || true)
  if echo "$EVENTS" | grep -q "Readiness probe failed"; then
    echo "Scenario misconfigured_readiness_probe ready — readiness probe failure event found (attempt ${ATTEMPT})"
    exit 0
  fi
  [ $((ATTEMPT % 10)) -eq 0 ] && echo "  attempt ${ATTEMPT}/60 — waiting…"
  sleep 1
done

echo "ERROR: Readiness probe failure not detected within 60s"
oc describe pod "$POD_NAME" -n "$NS"
oc get events -n "$NS" --sort-by='.lastTimestamp' | tail -15
exit 1
