#!/usr/bin/env bash
set -euo pipefail

VENV_DIR="${VENV_DIR:-$(cd "$(dirname "$0")/.." && pwd)/venv}"

if [ -f "${VENV_DIR}/bin/lightspeed-eval" ]; then
  echo "venv already exists at ${VENV_DIR}"
  exit 0
fi

# lightspeed-evaluation requires Python >=3.11,<3.14
PYTHON=""
for v in python3.13 python3.12 python3.11; do
  if command -v "$v" >/dev/null 2>&1; then
    PYTHON="$v"
    break
  fi
done

if [ -z "$PYTHON" ]; then
  printf '\033[0;31mERROR:\033[0m Python 3.11–3.13 required (lightspeed-evaluation does not support 3.14+).\n'
  printf '  Install with: sudo dnf install python3.13\n'
  exit 1
fi

echo "Creating venv with ${PYTHON} at ${VENV_DIR}..."
"$PYTHON" -m venv "$VENV_DIR"
"${VENV_DIR}/bin/pip" install --quiet git+https://github.com/lightspeed-core/lightspeed-evaluation.git
printf '\033[0;32mDone.\033[0m venv ready at %s\n' "$VENV_DIR"
