# netobserv evaluation scenarios

# Scenarios (must match tag: values in evals.yaml)
SCENARIOS = dns_latency \
            dns_nxdomain \
            packet_drops_kernel \
            packet_drops_policy \
            tls_issues \
            tcp_rtt

# MCP config
MCP_TOOLSETS = core,config,netobserv

# Shared infrastructure
include ../scripts/eval.mk

# Suite infrastructure (NetObserv operator)
include build/netobserv.mk

# Setup: shared infra + NetObserv operator + FlowCollector
.PHONY: setup
setup: _setup-shared
	$(MAKE) setup-netobserv-openshift

# Cleanup: NetObserv operator + shared infra
.PHONY: cleanup
cleanup:
	$(MAKE) clean-netobserv-openshift
	$(MAKE) _cleanup-shared
