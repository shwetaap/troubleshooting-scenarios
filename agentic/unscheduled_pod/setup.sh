#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="user-imports"
DEPLOY="user-profile-import"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

# Wait for FailedScheduling event on the pod
echo "Waiting for FailedScheduling event on $DEPLOY pods…"
ATTEMPT=0
until [ "$ATTEMPT" -ge 60 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  REASONS=$(oc get events -n "$NS" \
    --field-selector "reason=FailedScheduling" \
    -o jsonpath='{.items[*].reason}' 2>/dev/null || true)
  if echo "$REASONS" | grep -q "FailedScheduling"; then
    echo "Setup complete: FailedScheduling event detected (attempt $ATTEMPT)"
    exit 0
  fi
  sleep 1
done

echo "FailedScheduling event not detected within 60s"
oc get events -n "$NS"
exit 1
