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

# Snapshot existing JSON files before runs
existing_jsons=$(find "$RESULTS_DIR" -maxdepth 1 -name '*_summary.json' 2>/dev/null | sort)

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

# Find new JSON files produced by this batch
new_jsons=$(find "$RESULTS_DIR" -maxdepth 1 -name '*_summary.json' 2>/dev/null | sort)
batch_jsons=$(comm -13 <(echo "$existing_jsons") <(echo "$new_jsons"))

if [ -n "$batch_jsons" ]; then
  echo ""
  echo "==> Generating summary..."
  # shellcheck disable=SC2086
  "${VENV_DIR}/bin/python" "${SCRIPT_DIR}/summarize-agentic-evals.py" "$RESULTS_DIR" "$EVALS" $batch_jsons
fi

echo ""
echo "==> All agentic evals complete. Results in ${RESULTS_DIR}/"
