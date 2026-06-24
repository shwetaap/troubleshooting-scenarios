# <suite-name> evaluation scenarios
#
# Usage:
#   make setup     Install venv + OLS + MCP + suite dependencies
#   make evals     Run all scenarios
#   make cleanup  Remove suite dependencies + MCP

# Scenarios (must match tag: values in evals.yaml)
SCENARIOS = _example_scenario

# MCP config
# Toolsets beyond core,config that your evals need (comma-separated)
MCP_TOOLSETS = core,config
# Uncomment for kiali/OSSM toolset:
# MCP_TOOLSETS = core,config,ossm
# MCP_KIALI_URL = https://kiali.istio-system:20001/

# Shared infrastructure
include ../scripts/eval.mk

# Setup: shared infra + suite dependencies
.PHONY: setup
setup: _setup-shared
	@echo "Add suite-specific cluster setup here (e.g. operator install, CR apply)"

# Cleanup: suite dependencies + shared infra
.PHONY: cleanup
cleanup:
	@echo "Add suite-specific cleanup here"
	$(MAKE) _cleanup-shared
