#!/bin/bash
set -e

echo "Scenario 03 — Image Pull Failure"
echo ""

echo "=== Introducing image typo ==="
echo "  Setting image to registry.redhat.io/ubi9/ubi9:latest (typo: ubi9 instead of ubi)..."
oc set image deployment/inventory-app -n inventory \
  inventory-app=registry.redhat.io/ubi9/ubi9:latest

echo ""
echo "Waiting for ImagePullBackOff..."
while true; do
  STATUS=$(oc get pods -n inventory -l app=inventory-app \
    -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' 2>/dev/null || echo "")
  if echo "$STATUS" | grep -qE "ImagePullBackOff|ErrImagePull"; then
    echo "  Pods are in ImagePullBackOff."
    break
  fi
  sleep 5
done

echo ""
echo "PDB status:"
oc get pdb -n inventory

TOKEN=$(oc whoami -t)
THANOS_HOST=$(oc -n openshift-monitoring get route thanos-querier -o jsonpath='{.spec.host}')

echo ""
echo "Waiting for InventoryPodImagePullBackOff alert to fire (~30s)..."
while true; do
  ALERT_COUNT=$(curl -sk -H "Authorization: Bearer ${TOKEN}" \
    "https://${THANOS_HOST}/api/v1/alerts" 2>/dev/null |
    python3 -c "
import sys, json
data = json.load(sys.stdin)
print(sum(1 for a in data.get('data',{}).get('alerts',[])
          if a['labels'].get('namespace')=='inventory'
          and a['state']=='firing'))" 2>/dev/null || echo "0")
  echo "  Firing alerts in inventory namespace: ${ALERT_COUNT}"
  if [ "$ALERT_COUNT" -ge 1 ] 2>/dev/null; then
    break
  fi
  sleep 10
done

echo ""
echo "Done. InventoryPodImagePullBackOff alert is firing."
echo "Note: The platform PodDisruptionBudgetLimit (critical) alert will fire after ~15 minutes."
echo ""
echo "Pod status:"
oc get pods -n inventory -l app=inventory-app
