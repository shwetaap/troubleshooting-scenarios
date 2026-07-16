#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="catalog-mgmt"
JOB="inventory-sync-validator"

echo "Applying batch_failure scenario manifests in namespace ${NS}…"
oc apply -f "$FIXTURE_DIR/job.yaml"
oc create secret generic inventory-sync-logs-script \
  --from-file=generate_logs.py="$FIXTURE_DIR/generate_logs.py" \
  -n "$NS" --dry-run=client -o yaml | oc apply -f -

echo "Waiting for job log sentinels (up to 60s)…"
ATTEMPT=0
until [ "$ATTEMPT" -ge 20 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  LOGS=$(oc logs -l "job-name=$JOB" -n "$NS" --tail=100 2>/dev/null || true)
  if echo "$LOGS" | grep -q "Target host: prod-db, port: 3333" \
  && echo "$LOGS" | grep -q "FATAL: Unable to connect to required database"; then
    echo "Scenario batch_failure ready — both sentinels found (attempt ${ATTEMPT})"
    exit 0
  fi
  [ $((ATTEMPT % 10)) -eq 0 ] && echo "  attempt ${ATTEMPT}/20 — waiting…"
  sleep 3
done

echo "ERROR: Sentinels not found within 60s"
oc logs -l "job-name=$JOB" -n "$NS" --tail=30 2>/dev/null || true
exit 1
