#!/usr/bin/env bash
set -euo pipefail

OLS_NS="${OLS_NS:-openshift-lightspeed}"

echo "==> Removing OLS from ${OLS_NS}..."

oc delete olsconfig cluster --ignore-not-found 2>/dev/null || true
oc delete secret credentials-openai -n "$OLS_NS" --ignore-not-found 2>/dev/null || true

# Remove Subscription + CSV
CSV=$(oc get subscription lightspeed-operator -n "$OLS_NS" \
  -o jsonpath='{.status.currentCSV}' 2>/dev/null || true)
oc delete subscription lightspeed-operator -n "$OLS_NS" --ignore-not-found 2>/dev/null || true
if [ -n "$CSV" ]; then
  oc delete csv "$CSV" -n "$OLS_NS" --ignore-not-found 2>/dev/null || true
fi

oc delete operatorgroup openshift-lightspeed -n "$OLS_NS" --ignore-not-found 2>/dev/null || true
oc delete namespace "$OLS_NS" --ignore-not-found 2>/dev/null || true

echo "==> OLS teardown complete."
