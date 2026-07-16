#!/usr/bin/env bash
set -euo pipefail

NS="service-mesh"

echo "Removing timeout_connections scenario resources from namespace ${NS}…"
oc delete deployment frontend -n "$NS" --ignore-not-found
oc delete deployment backend -n "$NS" --ignore-not-found
oc delete svc backend-service -n "$NS" --ignore-not-found
oc delete networkpolicy backend-network-policy -n "$NS" --ignore-not-found

oc delete namespace "$NS" --ignore-not-found
echo "Cleanup complete — all timeout_connections scenario resources removed."
