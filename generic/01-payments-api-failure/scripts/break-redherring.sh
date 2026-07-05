#!/bin/bash
set -e

echo "Scenario 01 — Payments API Failure"
echo ""

if oc get namespace shared-services &>/dev/null; then
  SERVICES_NS="shared-services"
else
  SERVICES_NS="payments"
fi

echo "=== Misconfiguring probes on reconciliation-service ==="
oc set probe deployment/reconciliation-service -n "$SERVICES_NS" \
  --readiness --get-url=http://:8443/ --initial-delay-seconds=3 --period-seconds=5 --failure-threshold=3
oc set probe deployment/reconciliation-service -n "$SERVICES_NS" \
  --liveness --get-url=http://:8443/ --initial-delay-seconds=3 --period-seconds=5 --failure-threshold=3

oc -n "$SERVICES_NS" rollout status deployment/reconciliation-service --timeout=60s || true

echo ""
echo "Done. reconciliation-service will enter CrashLoopBackOff (probes on wrong port)."
