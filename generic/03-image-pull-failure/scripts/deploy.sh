#!/bin/bash
set -e

echo "Scenario 03 — Image Pull Failure"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "=== Enabling user workload monitoring ==="
oc apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
EOF

echo ""
echo "=== Cleaning up existing namespace ==="
oc delete namespace inventory --ignore-not-found --wait

echo ""
echo "=== Creating namespace ==="
oc apply -f manifests/00-namespace.yaml

echo ""
echo "=== Deploying inventory-app ==="
oc apply -f manifests/01-inventory-app.yaml
oc apply -f manifests/02-pdb.yaml
oc apply -f manifests/03-prometheusrules.yaml

echo ""
echo "=== Waiting for deployment to be ready ==="
echo "  Waiting for inventory-app..."
oc -n inventory wait --for=condition=available deployment/inventory-app --timeout=120s

echo ""
echo "Done. All pods running in the 'inventory' namespace."
echo ""
echo "PDB status:"
oc get pdb -n inventory
