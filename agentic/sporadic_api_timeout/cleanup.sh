#!/usr/bin/env bash
set -euo pipefail

NS="analytics-platform"

echo "Removing sporadic_api_timeout scenario resources from namespace ${NS}…"
oc delete statefulset report-generator -n "$NS" --ignore-not-found --wait=false
oc delete secret report-generator-logs-script -n "$NS" --ignore-not-found

oc delete namespace "$NS" --ignore-not-found
echo "Cleanup complete — all sporadic_api_timeout scenario resources removed."
