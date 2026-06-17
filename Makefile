##@ Lightspeed evaluation environment
.PHONY: setup-ols-evaluation
setup-ols-evaluation: venv/bin/activate ## Create venv and install lightspeed-evaluation

venv/bin/activate:
	@command -v python3 >/dev/null 2>&1 || \
	  { printf '\033[0;31mERROR:\033[0m python3 not found in PATH.\n'; exit 1; }
	@# lightspeed-evaluation requires Python >=3.11,<3.14 — prefer 3.13/3.12/3.11
	$(eval PYTHON := $(shell \
	  for v in python3.13 python3.12 python3.11; do \
	    command -v $$v 2>/dev/null && break; \
	  done))
	@[ -n "$(PYTHON)" ] || \
	  { printf '\033[0;31mERROR:\033[0m Python 3.11–3.13 required (lightspeed-evaluation does not support 3.14+).\n'; \
	    printf '  Install with: sudo dnf install python3.13\n'; exit 1; }
	@printf 'Using %s\n' "$(PYTHON)"
	$(PYTHON) -m venv venv
	venv/bin/pip install --quiet git+https://github.com/lightspeed-core/lightspeed-evaluation.git
	@printf '\033[0;32mDone.\033[0m venv ready at ./venv\n'

##@ OpenShift MCP Server

MCP_NS        ?= openshift-mcp
OLS_NS        ?= openshift-lightspeed
MCP_ISTIO_NS  ?= istio-system
OPENSHIFT_MCP_INTERNAL_IMAGE="registry.redhat.io/openshift-lightspeed/openshift-mcp-server-rhel9@sha256:83f288c04aad9c742cf2cee51f45e1be1982e1fcc388d2112cf5483e381fff62"
#
#  Enable toolsets for the OpenShift MCP server: core and config
#  Add additional toolsets to the list by setting TOOLSETS_ADDITIONAL separated by commas
#
TOOLSETS_ADDITIONAL ?= ossm

.PHONY: setup-openshift-mcp
setup-openshift-mcp: ## Deploy the OpenShift MCP server (namespace, RBAC, config, deployment, route)
	@set -e; \
	ns='$(MCP_NS)'; \
	echo "==> Creating namespace $$ns..."; \
	oc create namespace "$$ns" --dry-run=client -o yaml | oc apply -f -; \
	echo "==> Creating ServiceAccount..."; \
	{ \
	  echo 'apiVersion: v1'; \
	  echo 'kind: ServiceAccount'; \
	  echo 'metadata:'; \
	  echo '  name: openshift-mcp-server'; \
	  echo "  namespace: $$ns"; \
	} | oc apply -f -; \
	echo "==> Granting cluster-admin to ServiceAccount..."; \
	oc create clusterrolebinding openshift-mcp-server-admin \
	  --clusterrole=cluster-admin \
	  "--serviceaccount=$$ns:openshift-mcp-server" \
	  --dry-run=client -o yaml | oc apply -f -; \
	oc adm policy add-cluster-role-to-user cluster-admin \
	  "system:serviceaccount:$$ns:openshift-mcp-server"
	$(MAKE) mcp-config
	@set -e; \
	ns='$(MCP_NS)'; \
	image='$(OPENSHIFT_MCP_INTERNAL_IMAGE)'; \
	echo "==> Creating Deployment..."; \
	{ \
	  echo 'apiVersion: apps/v1'; \
	  echo 'kind: Deployment'; \
	  echo 'metadata:'; \
	  echo '  name: openshift-mcp-server'; \
	  echo "  namespace: $$ns"; \
	  echo 'spec:'; \
	  echo '  replicas: 1'; \
	  echo '  selector:'; \
	  echo '    matchLabels:'; \
	  echo '      app: openshift-mcp-server'; \
	  echo '  template:'; \
	  echo '    metadata:'; \
	  echo '      labels:'; \
	  echo '        app: openshift-mcp-server'; \
	  echo '    spec:'; \
	  echo '      serviceAccountName: openshift-mcp-server'; \
	  echo '      containers:'; \
	  echo '      - name: openshift-mcp-server'; \
	  echo "        image: $$image"; \
	  echo '        command: ["/openshift-mcp-server"]'; \
	  echo '        args: ["--config", "/etc/mcp/config.toml"]'; \
	  echo '        ports:'; \
	  echo '        - containerPort: 8080'; \
	  echo '        volumeMounts:'; \
	  echo '        - name: mcp-config'; \
	  echo '          mountPath: /etc/mcp'; \
	  echo '      volumes:'; \
	  echo '      - name: mcp-config'; \
	  echo '        configMap:'; \
	  echo '          name: mcp-config'; \
	} | oc apply -f -; \
	echo "==> Creating Service..."; \
	{ \
	  echo 'apiVersion: v1'; \
	  echo 'kind: Service'; \
	  echo 'metadata:'; \
	  echo '  name: openshift-mcp-server'; \
	  echo "  namespace: $$ns"; \
	  echo 'spec:'; \
	  echo '  selector:'; \
	  echo '    app: openshift-mcp-server'; \
	  echo '  ports:'; \
	  echo '  - port: 8080'; \
	  echo '    targetPort: 8080'; \
	} | oc apply -f -; \
	echo "==> Exposing OpenShift Route..."; \
	oc get route openshift-mcp-server -n "$$ns" &>/dev/null \
	  || oc expose service openshift-mcp-server -n "$$ns"; \
	route_host="$$(oc get route openshift-mcp-server -n "$$ns" \
	  -o jsonpath='{.spec.host}' 2>/dev/null)"; \
	echo ""; \
	echo "==> MCP server installed! Endpoint: http://$$route_host";

.PHONY: mcp-config
mcp-config: ## Rebuild mcp-config ConfigMap and restart the pod if already running
	@set -e; \
	ns='$(MCP_NS)'; \
	istio_ns='$(MCP_ISTIO_NS)'; \
	additional="$$(printf '%s' '$(TOOLSETS_ADDITIONAL)' | tr -d '"')"; \
	echo "==> Building mcp-config ConfigMap (toolsets: core,config,$$additional)..."; \
	ts='["core","config"'; \
	IFS=,; \
	for t in $$additional; do \
	  ts="$$ts,\"$$t\""; \
	done; \
	unset IFS; \
	ts="$$ts]"; \
	printf 'toolsets = %s\nlog_level = 0\nport = "8080"\nread_only = false\n' "$$ts" > /tmp/_mcp-config.toml; \
	if printf '%s' ",$$additional," | grep -q ",ossm,"; then \
	  printf '\n[toolset_configs.kiali]\nurl = "https://kiali.%s:20001/"\ninsecure = true\n' "$$istio_ns" >> /tmp/_mcp-config.toml; \
	fi; \
	echo "==> config.toml:"; \
	cat /tmp/_mcp-config.toml; \
	oc create configmap mcp-config \
	  --from-file=config.toml=/tmp/_mcp-config.toml \
	  -n "$$ns" --dry-run=client -o yaml | oc apply -f -; \
	rm -f /tmp/_mcp-config.toml; \
	if oc get deployment openshift-mcp-server -n "$$ns" &>/dev/null; then \
	  echo "==> Restarting openshift-mcp-server to pick up new config..."; \
	  oc rollout restart deployment/openshift-mcp-server -n "$$ns"; \
	  oc rollout status deployment/openshift-mcp-server -n "$$ns"; \
	else \
	  echo "==> Deployment not found — skipping restart (run 'make setup-openshift-mcp' first)."; \
	fi

.PHONY: connect-ols-mcp
connect-ols-mcp: ## Patch OLSConfig/cluster to register the openshift-mcp MCP server and restart OLS
	@set -e; \
	mcp_url="http://openshift-mcp-server.$(MCP_NS):8080/mcp"; \
	echo "==> Patching OLSConfig/cluster with mcpServers (url=$$mcp_url)..."; \
	patch="$$(printf \
	  '{"spec":{"featureGates":["MCPServer"],"mcpServers":[{"name":"openshift-mcp","headers":[{"name":"kubernetes-authorization","valueFrom":{"type":"kubernetes"}}],"url":"%s","timeout":30}]}}' \
	  "$$mcp_url")"; \
	oc patch olsconfig cluster --type=merge -p "$$patch"; \
	echo "==> OLSConfig/cluster updated."; \
	echo "==> Restarting lightspeed-app-server to pick up new config..."; \
	oc rollout restart deployment/lightspeed-app-server -n "$(OLS_NS)"; \
	oc rollout status deployment/lightspeed-app-server -n "$(OLS_NS)"; \
	echo "==> OLS is ready."

.PHONY: teardown-openshift-mcp
teardown-openshift-mcp: ## Remove the OpenShift MCP server and disconnect it from OLS
	@set -e; \
	ns='$(MCP_NS)'; \
	echo "==> Disconnecting openshift-mcp from OLSConfig/cluster..."; \
	oc patch olsconfig cluster --type=json \
	  -p '[{"op":"remove","path":"/spec/mcpServers"}]' 2>/dev/null || true; \
	echo "==> Restarting lightspeed-app-server..."; \
	oc rollout restart deployment/lightspeed-app-server -n "$(OLS_NS)" 2>/dev/null || true; \
	echo "==> Removing MCP server resources from $$ns..."; \
	oc delete deployment  openshift-mcp-server -n "$$ns" --ignore-not-found; \
	oc delete service     openshift-mcp-server -n "$$ns" --ignore-not-found; \
	oc delete route       openshift-mcp-server -n "$$ns" --ignore-not-found; \
	oc delete configmap   mcp-config           -n "$$ns" --ignore-not-found; \
	oc delete clusterrolebinding openshift-mcp-server-admin --ignore-not-found; \
	oc delete serviceaccount openshift-mcp-server -n "$$ns" --ignore-not-found; \
	oc delete namespace "$$ns" --ignore-not-found; \
	echo "==> Teardown complete."
