##@ Linting

LINT_DIRS ?= generic kiali-ossm netobserv

.PHONY: lint lint-shell lint-yaml

lint: lint-shell lint-yaml ## Run all linters (shellcheck + yamllint)

lint-shell: ## Lint shell scripts with shellcheck
	@command -v shellcheck >/dev/null 2>&1 || \
	  { printf '\033[0;31mERROR:\033[0m shellcheck not found. Install: sudo dnf install ShellCheck\n'; exit 1; }
	@files=$$(find $(LINT_DIRS) -name '*.sh' -type f 2>/dev/null); \
	if [ -z "$$files" ]; then \
	  printf 'No .sh files found in: %s\n' "$(LINT_DIRS)"; \
	else \
	  printf '==> shellcheck %s file(s)\n' "$$(echo "$$files" | wc -w)"; \
	  echo "$$files" | xargs shellcheck; \
	fi

lint-yaml: ## Lint YAML files with yamllint
	@command -v yamllint >/dev/null 2>&1 || \
	  { printf '\033[0;31mERROR:\033[0m yamllint not found. Install: pip install yamllint\n'; exit 1; }
	@files=$$(find $(LINT_DIRS) -type f \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null); \
	if [ -z "$$files" ]; then \
	  printf 'No YAML files found in: %s\n' "$(LINT_DIRS)"; \
	else \
	  printf '==> yamllint %s file(s)\n' "$$(echo "$$files" | wc -w)"; \
	  echo "$$files" | xargs yamllint -c .yamllint.yml; \
	fi

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

##@ MCP servers (OpenShift vs kubernetes-mcp-server)

OLS_NS ?= openshift-lightspeed
MCP_ISTIO_NS ?= istio-system

# Namespaces — one MCP flavor per namespace
OPENSHIFT_MCP_NS ?= openshift-mcp
KUBERNETES_MCP_NS ?= kubernetes-mcp-server
MCP_NS ?= $(OPENSHIFT_MCP_NS)

# OpenShift MCP (fixed Red Hat image, Kiali/ossm evals — not overridable)
OPENSHIFT_MCP_INTERNAL_IMAGE = registry.redhat.io/openshift-lightspeed/openshift-mcp-server-rhel9@sha256:83f288c04aad9c742cf2cee51f45e1be1982e1fcc388d2112cf5483e381fff62
OPENSHIFT_MCP_TOOLSETS ?= ossm

# kubernetes-mcp-server (upstream image, NetObserv evals)
KUBERNETES_MCP_IMAGE ?= quay.io/containers/kubernetes_mcp_server:latest
KUBERNETES_MCP_TOOLSETS ?= netobserv

.PHONY: setup-openshift-mcp setup-kubernetes-mcp
setup-openshift-mcp: ## Deploy Red Hat openshift-mcp-server (namespace openshift-mcp)
	$(MAKE) _mcp-setup \
	  MCP_NS=$(OPENSHIFT_MCP_NS) \
	  MCP_DEPLOYMENT=openshift-mcp-server \
	  MCP_IMAGE=$(OPENSHIFT_MCP_INTERNAL_IMAGE) \
	  MCP_COMMAND=/openshift-mcp-server \
	  MCP_CONFIG_MOUNT=/etc/mcp \
	  TOOLSETS_ADDITIONAL=$(or $(TOOLSETS_ADDITIONAL),$(OPENSHIFT_MCP_TOOLSETS))

setup-kubernetes-mcp: ## Deploy upstream kubernetes-mcp-server (namespace kubernetes-mcp-server)
	$(MAKE) _mcp-setup \
	  MCP_NS=$(KUBERNETES_MCP_NS) \
	  MCP_DEPLOYMENT=kubernetes-mcp-server \
	  MCP_IMAGE=$(KUBERNETES_MCP_IMAGE) \
	  MCP_COMMAND=/app/kubernetes-mcp-server \
	  MCP_CONFIG_MOUNT=/etc/kubernetes-mcp-server \
	  TOOLSETS_ADDITIONAL=$(or $(TOOLSETS_ADDITIONAL),$(KUBERNETES_MCP_TOOLSETS))

.PHONY: _mcp-setup
_mcp-setup:
	@set -e; \
	ns='$(MCP_NS)'; \
	name='$(MCP_DEPLOYMENT)'; \
	echo "==> Creating namespace $$ns..."; \
	oc create namespace "$$ns" --dry-run=client -o yaml | oc apply -f -; \
	echo "==> Creating ServiceAccount $$name..."; \
	{ \
	  echo 'apiVersion: v1'; \
	  echo 'kind: ServiceAccount'; \
	  echo 'metadata:'; \
	  echo "  name: $$name"; \
	  echo "  namespace: $$ns"; \
	} | oc apply -f -; \
	echo "==> Granting cluster-admin to ServiceAccount..."; \
	oc create clusterrolebinding "$$name-admin" \
	  --clusterrole=cluster-admin \
	  "--serviceaccount=$$ns:$$name" \
	  --dry-run=client -o yaml | oc apply -f -; \
	oc adm policy add-cluster-role-to-user cluster-admin \
	  "system:serviceaccount:$$ns:$$name"
	$(MAKE) _mcp-config \
	  MCP_NS='$(MCP_NS)' \
	  MCP_DEPLOYMENT='$(MCP_DEPLOYMENT)' \
	  TOOLSETS_ADDITIONAL='$(TOOLSETS_ADDITIONAL)'
	@set -e; \
	ns='$(MCP_NS)'; \
	name='$(MCP_DEPLOYMENT)'; \
	image='$(MCP_IMAGE)'; \
	mcp_cmd='$(MCP_COMMAND)'; \
	config_mount='$(MCP_CONFIG_MOUNT)'; \
	config_file='$(MCP_CONFIG_MOUNT)/config.toml'; \
	echo "==> Creating Deployment $$name (image=$$image)..."; \
	{ \
	  echo 'apiVersion: apps/v1'; \
	  echo 'kind: Deployment'; \
	  echo 'metadata:'; \
	  echo "  name: $$name"; \
	  echo "  namespace: $$ns"; \
	  echo 'spec:'; \
	  echo '  replicas: 1'; \
	  echo '  selector:'; \
	  echo '    matchLabels:'; \
	  echo "      app: $$name"; \
	  echo '  template:'; \
	  echo '    metadata:'; \
	  echo '      labels:'; \
	  echo "        app: $$name"; \
	  echo '    spec:'; \
	  echo "      serviceAccountName: $$name"; \
	  echo '      containers:'; \
	  echo "      - name: $$name"; \
	  echo "        image: $$image"; \
	  echo "        command: [\"$$mcp_cmd\"]"; \
	  echo "        args: [\"--config\", \"$$config_file\"]"; \
	  echo '        ports:'; \
	  echo '        - containerPort: 8080'; \
	  echo '        volumeMounts:'; \
	  echo '        - name: mcp-config'; \
	  echo "          mountPath: $$config_mount"; \
	  echo '      volumes:'; \
	  echo '      - name: mcp-config'; \
	  echo '        configMap:'; \
	  echo '          name: mcp-config'; \
	} | oc apply -f -; \
	echo "==> Creating Service $$name..."; \
	{ \
	  echo 'apiVersion: v1'; \
	  echo 'kind: Service'; \
	  echo 'metadata:'; \
	  echo "  name: $$name"; \
	  echo "  namespace: $$ns"; \
	  echo 'spec:'; \
	  echo '  selector:'; \
	  echo "    app: $$name"; \
	  echo '  ports:'; \
	  echo '  - port: 8080'; \
	  echo '    targetPort: 8080'; \
	} | oc apply -f -; \
	echo "==> Exposing OpenShift Route..."; \
	oc get route "$$name" -n "$$ns" &>/dev/null \
	  || oc expose service "$$name" -n "$$ns"; \
	route_host="$$(oc get route "$$name" -n "$$ns" \
	  -o jsonpath='{.spec.host}' 2>/dev/null)"; \
	echo ""; \
	echo "==> MCP server installed in $$ns! Route: http://$$route_host"; \
	echo "==> In-cluster URL: http://$$name.$$ns.svc.cluster.local:8080/mcp"

.PHONY: mcp-config openshift-mcp-config kubernetes-mcp-config _mcp-config
mcp-config: openshift-mcp-config ## Alias: rebuild openshift-mcp ConfigMap

openshift-mcp-config: ## Rebuild openshift-mcp ConfigMap and restart the pod
	$(MAKE) _mcp-config \
	  MCP_NS=$(OPENSHIFT_MCP_NS) \
	  MCP_DEPLOYMENT=openshift-mcp-server \
	  TOOLSETS_ADDITIONAL=$(or $(TOOLSETS_ADDITIONAL),$(OPENSHIFT_MCP_TOOLSETS))

kubernetes-mcp-config: ## Rebuild kubernetes-mcp-server ConfigMap and restart the pod
	$(MAKE) _mcp-config \
	  MCP_NS=$(KUBERNETES_MCP_NS) \
	  MCP_DEPLOYMENT=kubernetes-mcp-server \
	  TOOLSETS_ADDITIONAL=$(or $(TOOLSETS_ADDITIONAL),$(KUBERNETES_MCP_TOOLSETS))

_mcp-config:
	@set -e; \
	ns='$(MCP_NS)'; \
	name='$(MCP_DEPLOYMENT)'; \
	istio_ns='$(MCP_ISTIO_NS)'; \
	additional="$$(printf '%s' '$(TOOLSETS_ADDITIONAL)' | tr -d '"')"; \
	echo "==> Building mcp-config in $$ns (toolsets: core,config,$$additional)..."; \
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
	if oc get deployment "$$name" -n "$$ns" &>/dev/null; then \
	  echo "==> Restarting $$name to pick up new config..."; \
	  oc rollout restart "deployment/$$name" -n "$$ns"; \
	  oc rollout status "deployment/$$name" -n "$$ns"; \
	else \
	  echo "==> Deployment $$name not found — skipping restart."; \
	fi

.PHONY: connect-ols-mcp connect-ols-openshift-mcp connect-ols-kubernetes-mcp _connect-ols-mcp
connect-ols-mcp: connect-ols-openshift-mcp ## Alias: register openshift-mcp in OLSConfig

connect-ols-openshift-mcp: ## Register openshift-mcp-server in OLSConfig/cluster
	$(MAKE) _connect-ols-mcp \
	  MCP_OLS_NAME=openshift-mcp \
	  MCP_URL=http://openshift-mcp-server.$(OPENSHIFT_MCP_NS):8080/mcp

connect-ols-kubernetes-mcp: ## Register kubernetes-mcp-server in OLSConfig/cluster
	$(MAKE) _connect-ols-mcp \
	  MCP_OLS_NAME=kubernetes-mcp \
	  MCP_URL=http://kubernetes-mcp-server.$(KUBERNETES_MCP_NS):8080/mcp

_connect-ols-mcp:
	@set -e; \
	echo "==> Patching OLSConfig/cluster (name=$(MCP_OLS_NAME), url=$(MCP_URL))..."; \
	patch="$$(printf \
	  '{"spec":{"featureGates":["MCPServer"],"mcpServers":[{"name":"%s","headers":[{"name":"kubernetes-authorization","valueFrom":{"type":"kubernetes"}}],"url":"%s","timeout":120}]}}' \
	  '$(MCP_OLS_NAME)' '$(MCP_URL)')"; \
	oc patch olsconfig cluster --type=merge -p "$$patch"; \
	echo "==> OLSConfig/cluster updated."; \
	echo "==> Restarting lightspeed-app-server to pick up new config..."; \
	oc rollout restart deployment/lightspeed-app-server -n "$(OLS_NS)"; \
	oc rollout status deployment/lightspeed-app-server -n "$(OLS_NS)"; \
	echo "==> OLS is ready."

.PHONY: teardown-openshift-mcp teardown-kubernetes-mcp _teardown-mcp
teardown-openshift-mcp: ## Remove openshift-mcp namespace and disconnect from OLS
	$(MAKE) _teardown-mcp \
	  MCP_NS=$(OPENSHIFT_MCP_NS) \
	  MCP_DEPLOYMENT=openshift-mcp-server \
	  MCP_OLS_NAME=openshift-mcp

teardown-kubernetes-mcp: ## Remove kubernetes-mcp-server namespace and disconnect from OLS
	$(MAKE) _teardown-mcp \
	  MCP_NS=$(KUBERNETES_MCP_NS) \
	  MCP_DEPLOYMENT=kubernetes-mcp-server \
	  MCP_OLS_NAME=kubernetes-mcp

_teardown-mcp:
	@set -e; \
	ns='$(MCP_NS)'; \
	name='$(MCP_DEPLOYMENT)'; \
	echo "==> Removing MCP server $(MCP_OLS_NAME) from OLSConfig/cluster..."; \
	oc patch olsconfig cluster --type=json \
	  -p='[{"op":"remove","path":"/spec/mcpServers"}]' 2>/dev/null || true; \
	echo "==> Restarting lightspeed-app-server..."; \
	oc rollout restart deployment/lightspeed-app-server -n "$(OLS_NS)" 2>/dev/null || true; \
	echo "==> Removing MCP resources from $$ns..."; \
	oc delete deployment  "$$name" -n "$$ns" --ignore-not-found; \
	oc delete service     "$$name" -n "$$ns" --ignore-not-found; \
	oc delete route       "$$name" -n "$$ns" --ignore-not-found; \
	oc delete configmap   mcp-config -n "$$ns" --ignore-not-found; \
	oc delete clusterrolebinding "$$name-admin" --ignore-not-found; \
	oc delete serviceaccount "$$name" -n "$$ns" --ignore-not-found; \
	oc delete namespace "$$ns" --ignore-not-found; \
	echo "==> Teardown complete ($$ns)."
