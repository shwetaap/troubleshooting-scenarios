#!/usr/bin/env bash
set -euo pipefail

MCP_NS="${MCP_NS:-openshift-mcp}"
MCP_DEPLOYMENT="${MCP_DEPLOYMENT:-openshift-mcp-server}"
MCP_IMAGE="${MCP_IMAGE:-registry.redhat.io/openshift-lightspeed/openshift-mcp-server-rhel9@sha256:83f288c04aad9c742cf2cee51f45e1be1982e1fcc388d2112cf5483e381fff62}"
MCP_COMMAND="${MCP_COMMAND:-/openshift-mcp-server}"
MCP_CONFIG_MOUNT="${MCP_CONFIG_MOUNT:-/etc/mcp}"
MCP_TOOLSETS="${MCP_TOOLSETS:-core,config}"
MCP_KIALI_URL="${MCP_KIALI_URL:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Creating namespace ${MCP_NS}..."
oc create namespace "$MCP_NS" --dry-run=client -o yaml | oc apply -f -

echo "==> Creating ServiceAccount ${MCP_DEPLOYMENT}..."
oc apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${MCP_DEPLOYMENT}
  namespace: ${MCP_NS}
EOF

echo "==> Granting cluster-admin to ServiceAccount..."
oc create clusterrolebinding "${MCP_DEPLOYMENT}-admin" \
  --clusterrole=cluster-admin \
  "--serviceaccount=${MCP_NS}:${MCP_DEPLOYMENT}" \
  --dry-run=client -o yaml | oc apply -f -

# Build config.toml
"${SCRIPT_DIR}/mcp-config.sh"

config_file="${MCP_CONFIG_MOUNT}/config.toml"

echo "==> Creating Deployment ${MCP_DEPLOYMENT}..."
oc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${MCP_DEPLOYMENT}
  namespace: ${MCP_NS}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${MCP_DEPLOYMENT}
  template:
    metadata:
      labels:
        app: ${MCP_DEPLOYMENT}
    spec:
      serviceAccountName: ${MCP_DEPLOYMENT}
      containers:
      - name: ${MCP_DEPLOYMENT}
        image: ${MCP_IMAGE}
        command: ["${MCP_COMMAND}"]
        args: ["--config", "${config_file}"]
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: mcp-config
          mountPath: ${MCP_CONFIG_MOUNT}
      volumes:
      - name: mcp-config
        configMap:
          name: mcp-config
EOF

echo "==> Creating Service ${MCP_DEPLOYMENT}..."
oc apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${MCP_DEPLOYMENT}
  namespace: ${MCP_NS}
spec:
  selector:
    app: ${MCP_DEPLOYMENT}
  ports:
  - port: 8080
    targetPort: 8080
EOF

echo ""
echo "==> MCP server ready in ${MCP_NS}"
echo "==> In-cluster: http://${MCP_DEPLOYMENT}.${MCP_NS}.svc.cluster.local:8080/mcp"
