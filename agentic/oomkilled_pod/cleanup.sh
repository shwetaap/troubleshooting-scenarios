#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc delete -f "$FIXTURE_DIR/prometheusrule.yaml" --ignore-not-found
oc delete -f "$FIXTURE_DIR/manifest.yaml" --ignore-not-found --wait=false
oc delete namespace data-processing --ignore-not-found

echo "Cleanup complete: removed data-processing namespace and resources"
