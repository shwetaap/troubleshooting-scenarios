##@ Linting

LINT_DIRS ?= generic kiali-ossm kubevirt netobserv

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

##@ Maintenance

OLS_NS ?= openshift-lightspeed
SCRIPTS_DIR := scripts

.PHONY: help cleanup

help: ## Show available targets
	@echo ""
	@echo "  Root targets (maintenance):"
	@echo "    make cleanup          Remove OLS operator + venv"
	@echo "    make lint             Run all linters"
	@echo ""
	@echo "  Per-team workflow (run from team directory):"
	@echo "    cd kiali-ossm && make setup && make evals && make cleanup"
	@echo "    cd kubevirt   && make setup && make evals && make cleanup"
	@echo "    cd netobserv  && make setup && make evals && make cleanup"
	@echo ""

cleanup: ## Remove OLS operator + local venv
	@OLS_NS=$(OLS_NS) bash $(SCRIPTS_DIR)/cleanup-ols.sh
	rm -rf venv
	@echo "venv removed."
