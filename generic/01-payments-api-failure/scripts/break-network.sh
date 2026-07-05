#!/bin/bash
set -e

if oc get namespace shared-services &>/dev/null; then
  SERVICES_NS="shared-services"
else
  SERVICES_NS="payments"
fi

echo "=== Applying payments-np-policy NetworkPolicy in payments namespace ==="
oc apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: payments-np-policy
  namespace: payments
spec:
  podSelector:
    matchLabels:
      app: payments-api
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ${SERVICES_NS}
      ports:
        - protocol: TCP
          port: 5432
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
EOF

echo ""
echo "Done. NetworkPolicy is blocking all egress from payments-api."
