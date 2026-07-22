.PHONY: help deploy break fix cleanup delete-history

help:
	@echo "Image Pull Failure Scenario"
	@echo ""
	@echo "Available targets:"
	@echo "  deploy            Deploy the initial healthy state"
	@echo "  break             Introduce image typo and wait for PDB alert"
	@echo "  fix               Restore correct image"
	@echo "  delete-history    Reset Prometheus TSDB and restart pods"
	@echo "  cleanup           Delete all demo resources"

deploy:
	@./scripts/deploy.sh

break:
	@./scripts/break.sh

fix:
	@./scripts/fix.sh

delete-history:
	@./scripts/delete-history.sh

cleanup:
	@./scripts/cleanup.sh
