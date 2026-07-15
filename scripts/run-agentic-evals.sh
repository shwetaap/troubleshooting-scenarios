#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --system-config FILE --evals FILE --results-dir DIR [--runs N] --tag TAG [--tag TAG ...]"
  exit 1
}

SYSTEM_CONFIG=""
EVALS=""
RESULTS_DIR=""
RUNS=1
TAGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --system-config) SYSTEM_CONFIG="$2"; shift 2 ;;
    --evals)         EVALS="$2"; shift 2 ;;
    --results-dir)   RESULTS_DIR="$2"; shift 2 ;;
    --runs)          RUNS="$2"; shift 2 ;;
    --tag)           TAGS+=("$2"); shift 2 ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[ -n "$SYSTEM_CONFIG" ] && [ -n "$EVALS" ] && [ -n "$RESULTS_DIR" ] && [ ${#TAGS[@]} -gt 0 ] || usage

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

mkdir -p "$RESULTS_DIR"

for run in $(seq 1 "$RUNS"); do
  for tag in "${TAGS[@]}"; do
    echo ""
    echo "==> Run ${run}/${RUNS}: ${tag}"
    "${VENV_DIR}/bin/lightspeed-eval" \
      --system-config "$SYSTEM_CONFIG" \
      --output-dir "$RESULTS_DIR" \
      --eval-data "$EVALS" \
      --tag "$tag"
  done
done
