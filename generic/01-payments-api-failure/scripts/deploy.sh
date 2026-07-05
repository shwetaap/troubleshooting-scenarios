#!/bin/bash
set -e

echo "Scenario 01 — Payments API Failure"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

if [ "${SINGLE_USER:-}" = "1" ] || [ "${SINGLE_NAMESPACE:-}" = "1" ]; then
  MANIFESTS=$(mktemp -d)
  trap 'rm -rf $MANIFESTS' EXIT
  cp -r manifests/* "$MANIFESTS/"
else
  MANIFESTS="manifests"
fi

if [ "${SINGLE_USER:-}" = "1" ]; then
  # Both services use a single "dbuser" account
  sed -i 's/PGUSER: reporting/PGUSER: dbuser/' "$MANIFESTS/shared-services/01-secrets.yaml"
  sed -i 's/PGPASSWORD: reporting123/PGPASSWORD: dbuser123/' "$MANIFESTS/shared-services/01-secrets.yaml"
  sed -i 's/PGUSER: payments/PGUSER: dbuser/' "$MANIFESTS/payments/01-secrets.yaml"
  sed -i 's/PGPASSWORD: payments123/PGPASSWORD: dbuser123/' "$MANIFESTS/payments/01-secrets.yaml"

  # Replace two CREATE USER/GRANT blocks with a single dbuser
  sed -i "/CREATE USER reporting/,/GRANT.*TO reporting;/c\\    CREATE USER dbuser WITH PASSWORD 'dbuser123';\n    GRANT SELECT ON ALL TABLES IN SCHEMA public TO dbuser;" \
    "$MANIFESTS/shared-services/02-postgres.yaml"
  sed -i "/CREATE USER payments/,/GRANT.*TO payments;/d" \
    "$MANIFESTS/shared-services/02-postgres.yaml"

  echo "=== Single-user mode: all services will use 'dbuser' ==="
fi

if [ "${SINGLE_NAMESPACE:-}" = "1" ]; then
  rm -f "$MANIFESTS/shared-services/00-namespace.yaml"

  sed -i 's/namespace: shared-services/namespace: payments/g' "$MANIFESTS/shared-services/"*.yaml

  sed -i 's/namespace="shared-services"/namespace="payments"/g' "$MANIFESTS/shared-services/05-prometheusrules.yaml"

  sed -i "/^  labels:$/a\\    openshift.io/user-monitoring: 'true'" "$MANIFESTS/payments/00-namespace.yaml"

  sed -i 's/postgres\.shared-services\.svc\.cluster\.local/postgres/' "$MANIFESTS/payments/02-payments-api.yaml"

  echo "=== Single-namespace mode: all services deploy to 'payments' ==="
fi

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
echo "=== Cleaning up existing namespaces ==="
oc delete namespace shared-services --ignore-not-found --wait
oc delete namespace payments --ignore-not-found --wait

if [ "${SINGLE_NAMESPACE:-}" = "1" ]; then
  echo ""
  echo "=== Deploying to payments namespace ==="
  oc apply -f "$MANIFESTS/payments/00-namespace.yaml"
  oc apply -f "$MANIFESTS/shared-services/"
  oc -n payments wait --for=condition=available deployment/postgres --timeout=120s
  oc -n payments wait --for=condition=available deployment/reporting-service --timeout=120s
  oc apply -f "$MANIFESTS/payments/"
  oc -n payments wait --for=condition=available deployment/payments-api --timeout=120s
else
  echo ""
  echo "=== Deploying shared-services ==="
  oc apply -f "$MANIFESTS/shared-services/"
  oc -n shared-services wait --for=condition=available deployment/postgres --timeout=120s
  oc -n shared-services wait --for=condition=available deployment/reporting-service --timeout=120s

  echo ""
  echo "=== Deploying payments ==="
  oc apply -f "$MANIFESTS/payments/"
  oc -n payments wait --for=condition=available deployment/payments-api --timeout=120s
fi

ROUTE=$(oc -n payments get route payments-api -o jsonpath='{.spec.host}')
echo ""
echo "Done. All pods running with v1.0.1."
echo "Swagger UI: http://${ROUTE}/docs"
echo "API:        http://${ROUTE}/api/v1/process-payment"
