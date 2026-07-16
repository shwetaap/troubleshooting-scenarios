#!/usr/bin/env bash
set -euo pipefail

NS="discovery-hub"

echo "Removing unready_pod scenario resources from namespace ${NS}…"
oc delete pod catalog-index-service -n "$NS" --ignore-not-found

oc delete namespace "$NS" --ignore-not-found
echo "Cleanup complete — all unready_pod scenario resources removed."
