#!/bin/bash
set -e

echo "Scenario 03 — Image Pull Failure"
echo ""

echo "=== Cleaning up ==="
oc delete namespace inventory --ignore-not-found --wait

echo ""
echo "Done."
