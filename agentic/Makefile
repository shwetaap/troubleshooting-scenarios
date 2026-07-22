SCRIPTS_DIR := $(realpath ../scripts)

SUITES ?= \
	refused_connections \
	crashlooping_pod \
	failed_job \
	failing_api \
	oomkilled_pod \
	pending_pvc \
	recurring_batch_failure \
	sporadic_api_timeout \
	timeout_connections \
	unbalanced_replicas \
	unready_pod \
	unscheduled_pod
RUNS ?= 1

.PHONY: setup evals cleanup help

ALERT_SUITES := crashlooping_pod oomkilled_pod pending_pvc unready_pod

setup:
	@$(SCRIPTS_DIR)/enable-uwm.sh
	@for suite in $(ALERT_SUITES); do \
	  echo "==> Deploying alert scenario: $$suite"; \
	  bash $$suite/setup.sh; \
	done
	@echo ""
	@echo "All alert scenarios deployed."
	$(SCRIPTS_DIR)/setup-venv.sh
	@echo ""
	@echo "NOTE: Install lightspeed-agentic-operator manually by following:"
	@echo "  https://github.com/openshift/lightspeed-agentic-operator/tree/main/hack/quickstart"
	@echo "This will be automated in the future."

evals:
	@for suite in $(SUITES); do \
	  if [ ! -d "$$suite" ]; then \
	    echo "Error: suite '$$suite' not found. Available suites:"; \
	    for d in */; do \
	      if [ -f "$$d/evals.yaml" ]; then echo "  $${d%/}"; fi; \
	    done; \
	    exit 1; \
	  fi; \
	done
	$(eval DATETIME := $(shell date +%Y%m%d_%H%M%S))
	$(eval LOGS_DIR := results/logs/$(DATETIME))
	$(eval SUMMARY := results/results_$(DATETIME).md)
	@for suite in $(SUITES); do \
	  echo "==> Setup: $$suite"; \
	  if [ -x $$suite/setup.sh ]; then bash $$suite/setup.sh; fi; \
	  echo "==> Suite: $$suite"; \
	  bash $(SCRIPTS_DIR)/run-agentic-evals.sh \
	    --system-config system.yaml \
	    --evals $$suite/evals.yaml \
	    --results-dir $(LOGS_DIR) \
	    --runs $(RUNS) \
	    --tag agentic_$$(echo $$suite | tr '-' '_'); \
	  echo "==> Cleanup: $$suite"; \
	  if [ -x $$suite/cleanup.sh ]; then bash $$suite/cleanup.sh; fi; \
	done
	@echo ""
	@echo "==> Generating summary..."
	@../venv/bin/python $(SCRIPTS_DIR)/summarize-agentic-evals.py \
	  $(LOGS_DIR) \
	  --output $(SUMMARY) \
	  $(foreach s,$(SUITES),$s/evals.yaml) \
	  $$(find $(LOGS_DIR) -name '*_summary.json' | sort)

cleanup:
	@for suite in $(SUITES); do \
	  if [ -x $$suite/cleanup.sh ]; then \
	    echo "==> Cleanup: $$suite"; \
	    bash $$suite/cleanup.sh; \
	  fi; \
	done
	rm -rf ../venv
	@echo "venv removed."

help:
	@echo "Usage: make <target> [RUNS=N]"
	@echo ""
	@echo "Targets:"
	@echo "  setup    Install venv (lightspeed-agentic-operator is manual for now)"
	@echo "  evals    Run all suites ($(SUITES))"
	@echo "  cleanup  Run suite cleanup scripts and remove venv"
	@echo "  help     Show this help"
	@echo ""
	@echo "Options:"
	@echo "  RUNS=N     Number of runs per suite (default: 1)"
	@echo "  SUITES=... Space-separated list of suites to run (default: all)"
