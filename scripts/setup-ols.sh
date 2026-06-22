#!/usr/bin/env bash
set -euo pipefail

OLS_NS="${OLS_NS:-openshift-lightspeed}"

if [ -z "${OPENAI_API_KEY:-}" ]; then
  printf '\033[0;31mERROR:\033[0m OPENAI_API_KEY not set (needed for OLS credentials secret).\n'
  exit 1
fi

# Check if OLS is already installed and healthy
if oc get deployment lightspeed-app-server -n "$OLS_NS" -o name >/dev/null 2>&1; then
  if oc rollout status deployment/lightspeed-app-server -n "$OLS_NS" --timeout=10s >/dev/null 2>&1; then
    echo "OLS already installed and running in ${OLS_NS}"
    exit 0
  fi
fi

echo "==> Installing OLS operator in ${OLS_NS}..."

# 1. Namespace
oc apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${OLS_NS}
  labels:
    openshift.io/cluster-monitoring: "true"
EOF

# 2. OperatorGroup
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-lightspeed
  namespace: ${OLS_NS}
spec:
  targetNamespaces:
    - ${OLS_NS}
EOF

# 3. Subscription
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: lightspeed-operator
  namespace: ${OLS_NS}
spec:
  channel: stable
  name: lightspeed-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# 4. Wait for operator
echo "==> Waiting for Subscription to resolve..."
oc wait --for=jsonpath='{.status.state}'=AtLatestKnown \
  subscription/lightspeed-operator -n "$OLS_NS" --timeout=300s

CSV=$(oc get subscription lightspeed-operator -n "$OLS_NS" \
  -o jsonpath='{.status.currentCSV}')
echo "==> Waiting for CSV ${CSV}..."
oc wait --for=jsonpath='{.status.phase}'=Succeeded \
  csv/"${CSV}" -n "$OLS_NS" --timeout=300s

# 5. LLM credentials
echo "==> Creating credentials secret..."
oc create secret generic credentials-openai \
  --namespace "$OLS_NS" \
  --from-literal=apitoken="${OPENAI_API_KEY}" \
  --type=Opaque \
  --dry-run=client -o yaml | oc apply -f -

# 6. OLSConfig
echo "==> Applying OLSConfig..."
oc apply -f - <<EOF
apiVersion: ols.openshift.io/v1alpha1
kind: OLSConfig
metadata:
  name: cluster
spec:
  llm:
    providers:
    - name: openai
      type: openai
      credentialsSecretRef:
        name: credentials-openai
      url: https://api.openai.com/v1
      models:
      - name: gpt-4o-mini
      - name: gpt-4o
      - name: gpt-4.1
      - name: gpt-5
      - name: gpt-5-mini
      - name: gpt-5.2
        parameters:
          tool_budget_ratio: 0.5
      - name: gpt-5.4
  ols:
    defaultModel: gpt-5.2
    defaultProvider: openai
    introspectionEnabled: false
EOF

# 7. Wait for OLS to be ready
echo "==> Waiting for lightspeed-app-server deployment to appear..."
elapsed=0
while ! oc get deployment lightspeed-app-server -n "$OLS_NS" -o name >/dev/null 2>&1; do
  if [ "$elapsed" -ge 300 ]; then
    echo "ERROR: lightspeed-app-server not created after 300s"
    exit 1
  fi
  echo "  ... waiting for lightspeed-app-server (${elapsed}/300s)"
  sleep 5
  elapsed=$((elapsed + 5))
done
echo "==> Waiting for rollout..."
oc rollout status deployment/lightspeed-app-server -n "$OLS_NS" --timeout=300s
echo "==> OLS installed and ready in ${OLS_NS}."
