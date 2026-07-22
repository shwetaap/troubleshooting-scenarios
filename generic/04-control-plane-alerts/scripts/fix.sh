#!/bin/bash
set -e

echo "Scenario 04 — Control Plane Alerts"
echo ""

echo "=== Fixing Insights Operator ==="
echo "  Removing misconfigured insights-config..."
oc delete configmap insights-config -n openshift-insights --ignore-not-found

echo ""
echo "=== Fixing NTP on master node ==="
MASTER_NODE=$(oc get nodes --selector=node-role.kubernetes.io/master -o jsonpath='{.items[0].metadata.name}')
echo "  Target node: ${MASTER_NODE}"
echo "  Re-enabling chronyd..."
oc debug "node/${MASTER_NODE}" -- chroot /host systemctl enable --now chronyd

echo ""
echo "Done. All control plane misconfigurations have been reverted."
