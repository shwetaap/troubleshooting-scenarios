#!/usr/bin/env bash
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "$0")/../../generic/01-payments-api-failure" && pwd)"

make -C "$SCENARIO_DIR" cleanup
