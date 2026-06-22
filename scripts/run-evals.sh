#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --system-config FILE --evals FILE --results-dir DIR --ols-url URL --tag TAG [--tag TAG ...]"
  exit 1
}

SYSTEM_CONFIG=""
EVALS=""
RESULTS_DIR=""
OLS_URL=""
OLS_NS="${OLS_NS:-openshift-lightspeed}"
TAGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --system-config) SYSTEM_CONFIG="$2"; shift 2 ;;
    --evals)         EVALS="$2"; shift 2 ;;
    --results-dir)   RESULTS_DIR="$2"; shift 2 ;;
    --ols-url)       OLS_URL="$2"; shift 2 ;;
    --tag)           TAGS+=("$2"); shift 2 ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[ -n "$SYSTEM_CONFIG" ] && [ -n "$EVALS" ] && [ -n "$RESULTS_DIR" ] && [ -n "$OLS_URL" ] && [ ${#TAGS[@]} -gt 0 ] || usage

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/../venv"

if [ ! -f "${VENV_DIR}/bin/lightspeed-eval" ]; then
  echo "ERROR: lightspeed-eval not found at ${VENV_DIR}/bin/lightspeed-eval"
  echo "Run setup first (make setup)"
  exit 1
fi

if [ -z "${OPENAI_API_KEY:-}" ]; then
  printf '\033[0;31mERROR:\033[0m OPENAI_API_KEY not set (needed for judge LLM)\n'
  exit 1
fi

# 1. Generate system-runtime.yaml with actual OLS_URL
mkdir -p "$RESULTS_DIR"
RUNTIME_CONFIG="${RESULTS_DIR}/system-runtime.yaml"
sed "s|^  api_base: .*|  api_base: ${OLS_URL}|" "$SYSTEM_CONFIG" > "$RUNTIME_CONFIG"

# 2. Auto port-forward if OLS_URL is localhost and not reachable
PF_PID=""
cleanup_pf() {
  if [ -n "$PF_PID" ]; then
    kill "$PF_PID" 2>/dev/null || true
    wait "$PF_PID" 2>/dev/null || true
  fi
}
trap cleanup_pf EXIT

if [[ "$OLS_URL" == https://localhost:* ]]; then
  port="${OLS_URL##*:}"
  # Remove any trailing path
  port="${port%%/*}"
  if ! curl -ksf --connect-timeout 2 "${OLS_URL}/docs" >/dev/null 2>&1; then
    echo "==> Starting port-forward to OLS (${OLS_NS}, localhost:${port} -> 8443)..."
    oc port-forward -n "$OLS_NS" deployment/lightspeed-app-server "${port}:8443" >/dev/null 2>&1 &
    PF_PID=$!
    sleep 3
  fi
fi

# 3. Wait for OLS endpoint
echo "==> Waiting for OLS at ${OLS_URL}..."
ok=false
for i in $(seq 1 30); do
  case "$OLS_URL" in
    https://*) check_cmd="curl -ksf" ;;
    *)         check_cmd="curl -sf" ;;
  esac
  if $check_cmd --connect-timeout 3 "${OLS_URL}/docs" >/dev/null 2>&1; then
    ok=true
    break
  fi
  sleep 2
done

if [ "$ok" != "true" ]; then
  printf '\033[0;31mERROR:\033[0m OLS not reachable at %s after 60s\n' "$OLS_URL"
  exit 1
fi
echo "==> OLS OK at ${OLS_URL}"

# 4. Run lightspeed-eval for each tag
AUTH_TOKEN="$(oc whoami -t 2>/dev/null || true)"

for tag in "${TAGS[@]}"; do
  echo ""
  echo "==> Running eval: ${tag}"
  API_KEY="$AUTH_TOKEN" "${VENV_DIR}/bin/lightspeed-eval" \
    --system-config "$RUNTIME_CONFIG" \
    --output-dir "$RESULTS_DIR" \
    --eval-data "$EVALS" \
    --tag "$tag"
done

echo ""
echo "==> All evals complete. Results in ${RESULTS_DIR}/"
