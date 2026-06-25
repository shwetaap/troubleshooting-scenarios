#!/usr/bin/env bash
set -euo pipefail
echo "Cleaning up example scenario..."
# oc delete -f "$(dirname "$0")/fixtures/manifest.yaml" --ignore-not-found
echo "Example scenario cleaned up."
