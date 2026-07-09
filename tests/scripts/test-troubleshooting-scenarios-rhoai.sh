#!/bin/bash
# CI job: provision RHOAI operators, GPU infrastructure, and vLLM model serving
# for troubleshooting-scenarios testing against a self-hosted Llama-3.1-8B-Instruct.
#
# When RHOAI_PROVISION=true, the script provisions RHOAI operators, GPU infra,
# and a vLLM model serving endpoint. The vLLM endpoint can then be used for
# troubleshooting scenario testing.
#
# Input environment variables:
#   RHOAI_PROVISION           - Set to "true" to enable RHOAI provisioning
#   HUGGING_FACE_HUB_TOKEN    - Download Llama 3.1 8B from HuggingFace
#   VLLM_API_KEY              - API key for the vLLM endpoint
#   OPENAI_API_KEY (optional) - For judge LLM if using evaluation framework

set -eou pipefail

DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi

# ── RHOAI provisioning (conditional) ──────────────────────────────────
RHOAI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/tests/rhoai"

if [[ "${RHOAI_PROVISION:-false}" == "true" ]]; then
  echo "===== RHOAI provisioning enabled ====="

  # Validate required env vars
  : "${HUGGING_FACE_HUB_TOKEN:?HUGGING_FACE_HUB_TOKEN must be set when RHOAI_PROVISION=true}"
  : "${VLLM_API_KEY:?VLLM_API_KEY must be set when RHOAI_PROVISION=true}"

  export RHOAI_NAMESPACE="${RHOAI_NAMESPACE:-troubleshooting-scenarios-rhoai}"

  # 1. Create NFD and NVIDIA namespaces (needed by operator subscriptions)
  echo "--> Creating NFD and NVIDIA namespaces..."
  oc apply -f "$RHOAI_DIR/manifests/namespaces/nfd.yaml"
  oc apply -f "$RHOAI_DIR/manifests/namespaces/nvidia-operator.yaml"

  # 2. Bootstrap operators (install 3 operators, wait for CSVs, create DSC)
  echo "--> Bootstrapping RHOAI operators..."
  "$RHOAI_DIR/scripts/bootstrap.sh" "$RHOAI_DIR"

  # 3. GPU setup (NFD instance, ClusterPolicy, wait for GPU capacity)
  echo "--> Setting up GPU..."
  "$RHOAI_DIR/scripts/gpu-setup.sh" "$RHOAI_DIR"

  # 4. Create vLLM namespace and secrets
  echo "--> Creating vLLM namespace and secrets..."
  oc get ns "$RHOAI_NAMESPACE" >/dev/null 2>&1 || oc create namespace "$RHOAI_NAMESPACE"

  oc create secret generic hf-token-secret \
    --from-file=token=<(printf '%s' "$HUGGING_FACE_HUB_TOKEN") \
    -n "$RHOAI_NAMESPACE" --dry-run=client -o yaml | oc apply -f -

  oc create secret generic vllm-api-key-secret \
    --from-file=key=<(printf '%s' "$VLLM_API_KEY") \
    -n "$RHOAI_NAMESPACE" --dry-run=client -o yaml | oc apply -f -

  # 5. Create vLLM chat template ConfigMap
  echo "--> Creating vLLM chat template ConfigMap..."
  CHAT_TEMPLATE_FILE="$(mktemp)"
  curl -fsSL -o "$CHAT_TEMPLATE_FILE" \
    https://raw.githubusercontent.com/vllm-project/vllm/main/examples/tool_chat_template_llama3.1_json.jinja \
    || { echo "Failed to download jinja template"; exit 1; }

  oc create configmap vllm-chat-template -n "$RHOAI_NAMESPACE" \
    --from-file=tool_chat_template_llama3.1_json.jinja="$CHAT_TEMPLATE_FILE" \
    --dry-run=client -o yaml | oc apply -n "$RHOAI_NAMESPACE" -f -

  # 6. Fetch vLLM image from RHOAI template
  echo "--> Fetching vLLM image..."
  source "$RHOAI_DIR/scripts/fetch-vllm-image.sh"

  # 7. Deploy vLLM (ServingRuntime + InferenceService)
  echo "--> Deploying vLLM..."
  "$RHOAI_DIR/scripts/deploy-vllm.sh" "$RHOAI_DIR"

  # 8. Get vLLM pod info and KSVC_URL
  echo "--> Getting vLLM pod info..."
  "$RHOAI_DIR/scripts/get-vllm-pod-info.sh"
  source pod.env
  export KSVC_URL
  echo "vLLM endpoint: $KSVC_URL"

  # 9. Write VLLM_API_KEY to temp file for future use
  RHOAI_KEY_FILE=$(mktemp)
  echo -n "$VLLM_API_KEY" > "$RHOAI_KEY_FILE"
  export RHOAI_PROVIDER_KEY_PATH="$RHOAI_KEY_FILE"

  echo "===== RHOAI provisioning complete ====="
  echo ""
  echo "RHOAI vLLM endpoint is available at: $KSVC_URL"
  echo "API key is stored in: $RHOAI_PROVIDER_KEY_PATH"
  echo ""
  echo "You can now run troubleshooting scenarios against this endpoint."
  echo ""
else
  echo "===== RHOAI provisioning disabled ====="
  echo "Set RHOAI_PROVISION=true to enable RHOAI infrastructure provisioning"
fi
# ── End RHOAI provisioning ────────────────────────────────────────────

function run_tests() {
  if [[ "${RHOAI_PROVISION:-false}" == "true" ]]; then
    echo "Validating RHOAI infrastructure..."
    : "${KSVC_URL:?KSVC_URL must be set before running RHOAI tests}"
    echo "✅ vLLM endpoint ready: $KSVC_URL"
    echo "Infrastructure validation passed. TODO: Add troubleshooting scenario test logic here"
  else
    echo "Running troubleshooting scenarios with default configuration..."
    echo "TODO: Add default test logic here"
  fi
}

function cleanup() {
  if [[ -n "${CHAT_TEMPLATE_FILE:-}" ]]; then
    rm -f "$CHAT_TEMPLATE_FILE"
  fi
  if [[ -n "${RHOAI_KEY_FILE:-}" ]]; then
    rm -f "$RHOAI_KEY_FILE"
  fi
}
trap cleanup EXIT

run_tests
