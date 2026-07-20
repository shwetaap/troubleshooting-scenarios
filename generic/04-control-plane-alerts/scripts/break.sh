#!/bin/bash
set -e

echo "Scenario 04 — Control Plane Alerts"
echo ""

echo "=== Breaking Insights Operator ==="
echo "  Applying misconfigured upload endpoint..."
oc apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: insights-config
  namespace: openshift-insights
data:
  config.yaml: |
    dataReporting:
      interval: 5m
      uploadEndpoint: https://console.redhat.com/api/platform/v2/upload
EOF

echo ""
echo "=== Breaking NTP on a master node ==="
MASTER_NODE=$(oc get nodes --selector=node-role.kubernetes.io/master -o jsonpath='{.items[0].metadata.name}')
echo "  Target node: ${MASTER_NODE}"
echo "  Disabling chronyd and shifting clock forward by 2 minutes..."
oc debug "node/${MASTER_NODE}" -- chroot /host bash -c "systemctl disable --now chronyd && date -s '+2 minutes'"

echo ""
echo "Done. Alerts may take a few minutes to fire."
