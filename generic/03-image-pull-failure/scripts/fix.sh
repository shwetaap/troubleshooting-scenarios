#!/bin/bash
set -e

echo "Scenario 03 — Image Pull Failure"
echo ""

echo "=== Fixing image typo ==="
echo "  Setting image to registry.redhat.io/ubi9/ubi:latest (correct image)..."
oc set image deployment/inventory-app -n inventory \
  inventory-app=registry.redhat.io/ubi9/ubi:latest

echo ""
echo "Waiting for rollout to complete..."
oc rollout status deployment/inventory-app -n inventory

echo ""
echo "Done. All pods are running with the correct image."
echo ""
echo "PDB status:"
oc get pdb -n inventory
