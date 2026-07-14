#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="analytics-platform"
APP="report-generator"

echo "Applying scheduled_outage_detection scenario manifests in namespace ${NS}…"
oc apply -f "$FIXTURE_DIR/manifest.yaml"
oc create secret generic report-generator-logs-script \
  --from-file=generate_logs.py="$FIXTURE_DIR/generate_logs.py" \
  -n "$NS" --dry-run=client -o yaml | oc apply -f -

logs_ready() {
  local logs
  logs=$(oc logs -l "app=$APP" -n "$NS" --tail=10000 2>/dev/null || true)
  echo "$logs" | grep "Detected repeated failures during 03:00-03:05 window" >/dev/null || return 1
  echo "$logs" | grep "System health check passed" >/dev/null || return 1
  echo "$logs" | grep "Job executed successfully in 167ms\." >/dev/null || return 1
}

echo "Waiting for log sentinels (up to 120s)…"
ATTEMPT=0
until logs_ready; do
  ATTEMPT=$((ATTEMPT + 1))
  if [ "$ATTEMPT" -ge 40 ]; then
    echo "ERROR: Sentinels not found after 40 checks"
    oc get pods -n "$NS"
    exit 1
  fi
  [ $((ATTEMPT % 10)) -eq 0 ] && echo "  attempt ${ATTEMPT}/40 — waiting…"
  sleep 3
done
echo "Scenario scheduled_outage_detection ready — all log sentinels present (attempt ${ATTEMPT})"
