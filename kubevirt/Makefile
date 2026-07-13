# kubevirt evaluation scenarios

# Scenarios (must match tag: values in evals.yaml)
SCENARIOS = vm_storage_failure vm_crashloop vm_migration_failure
KVM_SCENARIOS = vm_crashloop vm_migration_failure

# MCP config — kubevirt toolset needed for VM diagnostics
MCP_TOOLSETS = core,config,kubevirt

# KVM-aware evals: skip scenarios that require KVM when no devices are available
.PHONY: evals
evals:
	@if bash build/require-kvm.sh --check 2>/dev/null; then \
	  tags="$(foreach s,$(SCENARIOS),--tag $(s))"; \
	else \
	  echo "WARNING: No KVM devices on worker nodes. Skipping: $(KVM_SCENARIOS)"; \
	  tags="$(foreach s,$(filter-out $(KVM_SCENARIOS),$(SCENARIOS)),--tag $(s))"; \
	fi; \
	if [ -z "$$tags" ]; then echo "No scenarios to evaluate."; exit 0; fi; \
	bash $(SCRIPTS_DIR)/run-evals.sh \
	  --system-config $(SYSTEM_CONFIG) --evals $(EVALS) \
	  --results-dir $(RESULTS_DIR) --ols-url $(OLS_URL) \
	  $$tags

# Shared infrastructure (included after evals override to avoid recipe conflict)
include ../scripts/eval.mk

# Install CNV operator (idempotent — skips if already present)
.PHONY: install-cnv
install-cnv:
	@bash build/install-cnv.sh

# Setup: shared infra + install/verify OpenShift Virtualization + deploy broken VMs
.PHONY: setup
setup: _setup-shared install-cnv
	@bash build/check-cnv.sh
	@$(MAKE) setup-scenarios

# Cleanup: remove broken VMs + CNV operator + shared infra
.PHONY: cleanup
cleanup:
	@$(MAKE) cleanup-scenarios
	@bash build/uninstall-cnv.sh
	$(MAKE) _cleanup-shared

# Deploy all broken VM scenarios (stops on first failure)
.PHONY: setup-scenarios
setup-scenarios:
	@for s in $(SCENARIOS); do \
	  echo "==> Setting up $$s"; \
	  bash ./$$s/setup.sh || exit 1; \
	done

# Remove all scenario resources (reports failures but cleans all scenarios)
.PHONY: cleanup-scenarios
cleanup-scenarios:
	@failed=""; \
	for s in $(SCENARIOS); do \
	  echo "==> Cleaning up $$s"; \
	  if ! bash ./$$s/cleanup.sh 2>&1; then \
	    failed="$$failed $$s"; \
	    echo "    WARNING: cleanup of $$s returned an error"; \
	  fi; \
	done; \
	if [ -n "$$failed" ]; then \
	  echo "WARNING: cleanup errors in:$$failed"; \
	  exit 1; \
	fi
