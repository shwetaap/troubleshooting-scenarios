#!/bin/bash
set -euo pipefail

echo "Scenario 03 — Image Pull Failure"
echo ""

echo "=== Deleting Prometheus history ==="

PROM_PODS=(
  "openshift-monitoring:prometheus-k8s-0"
  "openshift-monitoring:prometheus-k8s-1"
  "openshift-user-workload-monitoring:prometheus-user-workload-0"
  "openshift-user-workload-monitoring:prometheus-user-workload-1"
)

for entry in "${PROM_PODS[@]}"; do
  NS="${entry%%:*}"
  POD="${entry##*:}"
  echo "  Cleaning ${NS}/${POD}..."
  oc exec -n "$NS" "$POD" -c prometheus -- \
    rm -rf /prometheus/wal /prometheus/chunks_head /prometheus/data 2>/dev/null || true
done

echo ""
echo "=== Restarting Prometheus pods ==="
oc delete pod prometheus-k8s-0 prometheus-k8s-1 -n openshift-monitoring --ignore-not-found
oc delete pod prometheus-user-workload-0 prometheus-user-workload-1 -n openshift-user-workload-monitoring --ignore-not-found

echo ""
echo "=== Deleting events in inventory namespace ==="
oc delete events --all -n inventory 2>/dev/null || true

echo ""
echo "=== Restarting demo pods ==="
oc delete pods --all -n inventory 2>/dev/null || true

echo ""
echo "Done."
