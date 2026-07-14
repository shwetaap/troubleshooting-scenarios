#!/usr/bin/env bash
set -euo pipefail

NS="discovery-hub"

echo "Removing misconfigured_readiness_probe scenario resources from namespace ${NS}…"
oc delete pod catalog-index-service -n "$NS" --ignore-not-found

oc delete namespace "$NS" --ignore-not-found
echo "Cleanup complete — all misconfigured_readiness_probe scenario resources removed."
