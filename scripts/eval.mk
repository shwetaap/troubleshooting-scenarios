# scripts/eval.mk — shared eval infrastructure
# Include from suite Makefiles: include ../scripts/eval.mk

SCRIPTS_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

# Defaults (teams override before include)

OLS_NS          ?= openshift-lightspeed
OLS_PORT        ?= 8443
OLS_URL         ?= https://localhost:$(OLS_PORT)
MCP_NS          ?= openshift-mcp
MCP_IMAGE       ?= registry.redhat.io/openshift-lightspeed/openshift-mcp-server-rhel9@sha256:83f288c04aad9c742cf2cee51f45e1be1982e1fcc388d2112cf5483e381fff62
MCP_DEPLOYMENT  ?= openshift-mcp-server
MCP_COMMAND     ?= /openshift-mcp-server
MCP_CONFIG_MOUNT ?= /etc/mcp
MCP_TOOLSETS    ?= core,config
MCP_KIALI_URL   ?=
MCP_OLS_NAME    ?= openshift-mcp
SYSTEM_CONFIG   ?= ./system.yaml
EVALS           ?= ./evals.yaml
RESULTS_DIR     ?= ./results

# Shared setup (venv + preflight + OLS + MCP + connect)

.PHONY: _setup-shared
_setup-shared:
	@bash $(SCRIPTS_DIR)/setup-venv.sh
	@bash $(SCRIPTS_DIR)/preflight.sh
	@OPENAI_API_KEY="$(OPENAI_API_KEY)" OLS_NS=$(OLS_NS) \
	  bash $(SCRIPTS_DIR)/setup-ols.sh
	@MCP_NS=$(MCP_NS) MCP_DEPLOYMENT=$(MCP_DEPLOYMENT) MCP_IMAGE=$(MCP_IMAGE) \
	  MCP_COMMAND=$(MCP_COMMAND) MCP_CONFIG_MOUNT=$(MCP_CONFIG_MOUNT) \
	  MCP_TOOLSETS=$(MCP_TOOLSETS) MCP_KIALI_URL=$(MCP_KIALI_URL) \
	  bash $(SCRIPTS_DIR)/setup-mcp.sh
	@MCP_NS=$(MCP_NS) MCP_DEPLOYMENT=$(MCP_DEPLOYMENT) MCP_OLS_NAME=$(MCP_OLS_NAME) \
	  OLS_NS=$(OLS_NS) \
	  bash $(SCRIPTS_DIR)/connect-ols-mcp.sh

# Shared teardown (disconnect + remove MCP; OLS stays)

.PHONY: _teardown-shared
_teardown-shared:
	@OLS_NS=$(OLS_NS) \
	  bash $(SCRIPTS_DIR)/disconnect-ols-mcp.sh
	@MCP_NS=$(MCP_NS) MCP_DEPLOYMENT=$(MCP_DEPLOYMENT) \
	  bash $(SCRIPTS_DIR)/teardown-mcp.sh

# Run all scenarios

.PHONY: evals
evals:
	@bash $(SCRIPTS_DIR)/run-evals.sh \
	  --system-config $(SYSTEM_CONFIG) --evals $(EVALS) \
	  --results-dir $(RESULTS_DIR) --ols-url $(OLS_URL) \
	  $(foreach s,$(SCENARIOS),--tag $(s))

# Auto-generated per-scenario targets

define _eval_target
.PHONY: $(1)-eval
$(1)-eval:
	@bash $(SCRIPTS_DIR)/run-evals.sh \
	  --system-config $(SYSTEM_CONFIG) --evals $(EVALS) \
	  --results-dir $(RESULTS_DIR) --ols-url $(OLS_URL) \
	  --tag $(1)
endef
$(foreach s,$(SCENARIOS),$(eval $(call _eval_target,$(s))))

# Help

.PHONY: help
help:
	@echo ""
	@echo "  make setup              Install venv + OLS + MCP + suite dependencies"
	@echo "  make evals              Run all scenarios"
	@$(foreach s,$(SCENARIOS),echo "  make $(s)-eval";)
	@echo "  make teardown           Remove suite dependencies + MCP"
	@echo ""
	@echo "  OLS_URL=$(OLS_URL)  (override with OLS_URL=https://...)"
	@echo ""
