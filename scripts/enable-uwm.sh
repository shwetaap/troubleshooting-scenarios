#!/usr/bin/env bash
set -euo pipefail

echo "Ensuring user workload monitoring is enabled..."
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
