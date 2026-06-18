# ──────────────────────────────────────────────────────────────────────────────
# netobserv/Makefile — NetObserv evaluation targets
#
# Run `make setup-ols-evaluation` from the repository root once to create
# ../venv with lightspeed-eval (not from lightspeed-service).
#
# OLS runs in-cluster on HTTPS port 8443 (not 8080). Reach it via Route or port-forward:
#   OLS_URL=$(make -s ols-route-url) make dns_nxdomain-test
#   make ols-port-forward   # https://localhost:8443
# ──────────────────────────────────────────────────────────────────────────────

EVALS = ./evals.yaml
RESULTS_DIR = ./results
SYSTEM_CONFIG_SRC = ./system.yaml
SYSTEM_CONFIG = $(RESULTS_DIR)/system-runtime.yaml

OLS_NS ?= openshift-lightspeed
OLS_ROUTE ?= ols
OLS_PORT ?= 8443
OLS_URL ?= https://localhost:$(OLS_PORT)

_AUTHTOKEN = $(shell oc whoami -t 2>/dev/null)

EVAL_BASE = API_KEY=$(_AUTHTOKEN) \
            ../venv/bin/lightspeed-eval \
            --system-config $(SYSTEM_CONFIG) \
            --output-dir $(RESULTS_DIR) \
            --eval-data $(EVALS)

$(SYSTEM_CONFIG): $(SYSTEM_CONFIG_SRC)
	@mkdir -p $(RESULTS_DIR)
	@sed 's|^  api_base: .*|  api_base: $(OLS_URL)|' $(SYSTEM_CONFIG_SRC) > $(SYSTEM_CONFIG)

.PHONY: check-ols ols-port-forward ols-route-url deploy-flowcollector
check-ols: ## Verify OLS API is reachable at OLS_URL (default https://localhost:8443)
	@printf 'Checking OLS at %s …\n' '$(OLS_URL)'
	@case '$(OLS_URL)' in \
	  https://*) curl -k -sf --connect-timeout 3 '$(OLS_URL)/docs' >/dev/null 2>&1 ;; \
	  *) curl -sf --connect-timeout 3 '$(OLS_URL)/docs' >/dev/null 2>&1 ;; \
	esac || \
	  { printf '\033[0;31mERROR:\033[0m OLS not reachable at %s\n' '$(OLS_URL)'; \
	    printf '\nOperator OLS listens on **HTTPS port 8443** (not 8080).\n\n'; \
	    printf 'Option A — cluster Route (no port-forward):\n'; \
	    printf '  OLS_URL=$$(make -s ols-route-url) make dns_nxdomain-test\n\n'; \
	    printf 'Option B — port-forward in another terminal:\n'; \
	    printf '  make ols-port-forward\n'; \
	    printf '  # oc port-forward -n %s deployment/lightspeed-app-server %s:8443\n\n' '$(OLS_NS)' '$(OLS_PORT)'; \
	    exit 1; }
	@printf 'OLS API OK at %s\n' '$(OLS_URL)'

ols-route-url: ## Print https:// URL for the openshift-lightspeed Route (eval OLS_URL)
	@host="$$(oc get route '$(OLS_ROUTE)' -n '$(OLS_NS)' -o jsonpath='{.spec.host}' 2>/dev/null)"; \
	if [ -z "$$host" ]; then \
	  printf 'ERROR: Route %s not found in %s\n' '$(OLS_ROUTE)' '$(OLS_NS)' >&2; \
	  exit 1; \
	fi; \
	printf 'https://%s\n' "$$host"

ols-port-forward: ## Forward in-cluster OLS (HTTPS 8443) to localhost:$(OLS_PORT)
	oc port-forward -n $(OLS_NS) deployment/lightspeed-app-server $(OLS_PORT):8443

.PHONY: deploy-flowcollector
deploy-flowcollector: ## Apply eval FlowCollector (sampling 1, features, MCP network policy)
	oc apply -f build/flowcollector.yaml
	oc wait flowcollector/cluster --for=condition=Ready --timeout=10m

.PHONY: test dns_latency-test dns_nxdomain-test packet_drops_kernel-test \
        packet_drops_policy-test tls_issues-test tcp_rtt-test

test: check-ols $(SYSTEM_CONFIG) \
      dns_latency-test \
      dns_nxdomain-test \
      packet_drops_kernel-test \
      packet_drops_policy-test \
      tls_issues-test \
      tcp_rtt-test

dns_latency-test: check-ols $(SYSTEM_CONFIG)
	$(EVAL_BASE) \
	  --tag dns_latency

dns_nxdomain-test: check-ols $(SYSTEM_CONFIG)
	$(EVAL_BASE) \
	  --tag dns_nxdomain

packet_drops_kernel-test: check-ols $(SYSTEM_CONFIG)
	$(EVAL_BASE) \
	  --tag packet_drops_kernel

packet_drops_policy-test: check-ols $(SYSTEM_CONFIG)
	$(EVAL_BASE) \
	  --tag packet_drops_policy

tls_issues-test: check-ols $(SYSTEM_CONFIG)
	$(EVAL_BASE) \
	  --tag tls_issues

tcp_rtt-test: check-ols $(SYSTEM_CONFIG)
	$(EVAL_BASE) \
	  --tag tcp_rtt
