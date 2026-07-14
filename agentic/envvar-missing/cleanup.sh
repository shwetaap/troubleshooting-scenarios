#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc delete -f "$FIXTURE_DIR/deployment.yaml" --ignore-not-found --wait=false
oc delete namespace warehouse-ops --ignore-not-found

echo "Cleanup complete: removed warehouse-ops namespace and resources"
