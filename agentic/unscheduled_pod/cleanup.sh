#!/usr/bin/env bash
set -euo pipefail

NS="user-imports"

oc delete deployment user-profile-import -n "$NS" --ignore-not-found
oc delete namespace "$NS" --ignore-not-found

echo "Cleanup complete: removed user-imports namespace and resources"
