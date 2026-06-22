##@ NetObserv install

NETOBSERV_INSTALL_SCRIPT := $(abspath $(CURDIR)/build/scripts/install-netobserv-release.sh)
NETOBSERV_NS ?= netobserv
NETOBSERV_OPERATOR_NS ?= openshift-netobserv-operator
KUBERNETES_CLI ?= oc
NETOBSERV_CATALOG_SOURCE ?= redhat
NETOBSERV_CHANNEL ?=
NETOBSERV_FLOWCOLLECTOR_FILE ?= $(abspath $(CURDIR)/build/flowcollector.yaml)
NETOBSERV_FLOWCOLLECTOR_WAIT_TIMEOUT ?= 10m
NETOBSERV_DELETE_OPERATOR_NAMESPACE ?= yes

NETOBSERV_INSTALL_FLAGS = -c '$(KUBERNETES_CLI)' \
  -ns '$(NETOBSERV_NS)' \
  -ons '$(NETOBSERV_OPERATOR_NS)' \
  -cs '$(NETOBSERV_CATALOG_SOURCE)' \
  -fc '$(NETOBSERV_FLOWCOLLECTOR_FILE)'

ifneq ($(strip $(NETOBSERV_CHANNEL)),)
NETOBSERV_INSTALL_FLAGS += -ch '$(NETOBSERV_CHANNEL)'
endif

.PHONY: setup-netobserv-openshift
setup-netobserv-openshift: ## OpenShift: install NetObserv operator and eval FlowCollector
	@test -f '$(NETOBSERV_INSTALL_SCRIPT)' || { echo "Missing $(NETOBSERV_INSTALL_SCRIPT)"; exit 1; }
	@echo "==> NetObserv: installing operator (catalog=$(NETOBSERV_CATALOG_SOURCE)) ..."
	NETOBSERV_FLOWCOLLECTOR_WAIT_TIMEOUT='$(NETOBSERV_FLOWCOLLECTOR_WAIT_TIMEOUT)' \
	  bash '$(NETOBSERV_INSTALL_SCRIPT)' $(NETOBSERV_INSTALL_FLAGS) install
	@echo "==> setup-netobserv-openshift: done."

.PHONY: netobserv-install-operator netobserv-install-flowcollector
netobserv-install-operator: ## Install only the NetObserv operator via OLM
	@test -f '$(NETOBSERV_INSTALL_SCRIPT)' || { echo "Missing $(NETOBSERV_INSTALL_SCRIPT)"; exit 1; }
	bash '$(NETOBSERV_INSTALL_SCRIPT)' $(NETOBSERV_INSTALL_FLAGS) install-operator

netobserv-install-flowcollector: ## Apply eval FlowCollector and wait for Ready
	@test -f '$(NETOBSERV_INSTALL_SCRIPT)' || { echo "Missing $(NETOBSERV_INSTALL_SCRIPT)"; exit 1; }
	NETOBSERV_FLOWCOLLECTOR_WAIT_TIMEOUT='$(NETOBSERV_FLOWCOLLECTOR_WAIT_TIMEOUT)' \
	  bash '$(NETOBSERV_INSTALL_SCRIPT)' $(NETOBSERV_INSTALL_FLAGS) install-flowcollector

.PHONY: netobserv-status
netobserv-status: ## Show NetObserv operator, Loki, and FlowCollector status
	@test -f '$(NETOBSERV_INSTALL_SCRIPT)' || { echo "Missing $(NETOBSERV_INSTALL_SCRIPT)"; exit 1; }
	bash '$(NETOBSERV_INSTALL_SCRIPT)' $(NETOBSERV_INSTALL_FLAGS) status

.PHONY: clean-netobserv-openshift
clean-netobserv-openshift: ## Remove eval FlowCollector and NetObserv operator
	@test -f '$(NETOBSERV_INSTALL_SCRIPT)' || { echo "Missing $(NETOBSERV_INSTALL_SCRIPT)"; exit 1; }
	@set -e; \
	flags='$(NETOBSERV_INSTALL_FLAGS)'; \
	echo "==> NetObserv: deleting FlowCollector ..."; \
	bash '$(NETOBSERV_INSTALL_SCRIPT)' $$flags delete-flowcollector; \
	echo "==> NetObserv: deleting operator ..."; \
	if [ '$(NETOBSERV_DELETE_OPERATOR_NAMESPACE)' = yes ]; then \
	  bash '$(NETOBSERV_INSTALL_SCRIPT)' $$flags -don delete-operator; \
	else \
	  bash '$(NETOBSERV_INSTALL_SCRIPT)' $$flags delete-operator; \
	fi; \
	echo "==> clean-netobserv-openshift: done."

ifeq ($(words $(MAKEFILE_LIST)),1)
.DEFAULT_GOAL := setup-netobserv-openshift
endif
