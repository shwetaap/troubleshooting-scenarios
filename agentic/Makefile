SCRIPTS_DIR := $(realpath ../scripts)

SUITES := api_failure envvar-missing networkpolicy storage-binding
RUNS ?= 1

.PHONY: setup evals

setup:
	$(SCRIPTS_DIR)/setup-venv.sh

evals:
	$(eval RESULTS_DIR := results/$(shell date +%Y%m%d_%H%M%S))
	@for suite in $(SUITES); do \
	  echo "==> Suite: $$suite"; \
	  bash $(SCRIPTS_DIR)/run-agentic-evals.sh \
	    --system-config $$suite/system.yaml \
	    --evals $$suite/evals.yaml \
	    --results-dir $(RESULTS_DIR) \
	    --runs $(RUNS) \
	    --tag agentic_$$(echo $$suite | tr '-' '_'); \
	done
