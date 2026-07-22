#!/bin/bash
# CI job: install lightspeed-agentic-operator, configure LLM providers,
# and run agentic troubleshooting evaluations.
#
# Input environment variables:
#   OPENAI_API_KEY                  - OpenAI API key (judge LLM + OpenAI agent)
#   GOOGLE_APPLICATION_CREDENTIALS  - Path to GCP service account JSON (Vertex AI)
#   VERTEX_PROJECT_ID               - GCP project ID (falls back to credentials JSON)
#   VERTEX_REGION                   - GCP region (default: us-east1)
#   SUITES                          - Space-separated scenario list (default: all)
#   ARTIFACT_DIR                    - CI artifact directory (default: /tmp/artifacts)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AGENTIC_DIR="${REPO_DIR}/agentic"
ARTIFACT_DIR="${ARTIFACT_DIR:-/tmp/artifacts}"
NAMESPACE="openshift-lightspeed"

function install_operator() {
    echo "==> Installing lightspeed-agentic-operator..."
    bash <(curl -sL https://raw.githubusercontent.com/openshift/lightspeed-agentic-operator/main/hack/quickstart/install.sh)
    echo "==> Operator installed."
}

function setup_openai() {
    : "${OPENAI_API_KEY:?OPENAI_API_KEY must be set}"

    oc create secret generic llm-creds-openai -n "$NAMESPACE" \
        --from-literal=OPENAI_API_KEY="$OPENAI_API_KEY" \
        --dry-run=client -o yaml | oc apply -f -

    oc apply -f - <<'EOF'
apiVersion: agentic.openshift.io/v1alpha1
kind: LLMProvider
metadata:
  name: openai
  namespace: openshift-lightspeed
spec:
  type: OpenAI
  openAI:
    credentialsSecret:
      name: llm-creds-openai
---
apiVersion: agentic.openshift.io/v1alpha1
kind: Agent
metadata:
  name: default
  namespace: openshift-lightspeed
spec:
  llmProvider:
    name: openai
  model: "gpt-5.4"
  timeouts:
    analysisSeconds: 600
    executionSeconds: 600
    verificationSeconds: 600
EOF
    echo "    OpenAI provider configured."
}

function setup_vertex() {
    : "${GOOGLE_APPLICATION_CREDENTIALS:?GOOGLE_APPLICATION_CREDENTIALS must be set}"

    if [[ ! -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
        echo "ERROR: GCP credentials file not found at $GOOGLE_APPLICATION_CREDENTIALS" >&2
        exit 1
    fi

    if [[ -z "${VERTEX_PROJECT_ID:-}" ]]; then
        VERTEX_PROJECT_ID=$(python3 -c "import json; print(json.load(open('$GOOGLE_APPLICATION_CREDENTIALS'))['project_id'])")
        echo "    Extracted project ID from credentials: $VERTEX_PROJECT_ID"
    fi
    VERTEX_REGION="${VERTEX_REGION:-us-east1}"

    oc create secret generic llm-creds-vertex -n "$NAMESPACE" \
        --from-file=GOOGLE_APPLICATION_CREDENTIALS="$GOOGLE_APPLICATION_CREDENTIALS" \
        --dry-run=client -o yaml | oc apply -f -

    oc apply -f - <<EOF
apiVersion: agentic.openshift.io/v1alpha1
kind: LLMProvider
metadata:
  name: vertex-anthropic
  namespace: $NAMESPACE
spec:
  type: GoogleCloudVertex
  googleCloudVertex:
    projectID: $VERTEX_PROJECT_ID
    region: $VERTEX_REGION
    modelProvider: Anthropic
    credentialsSecret:
      name: llm-creds-vertex
---
apiVersion: agentic.openshift.io/v1alpha1
kind: Agent
metadata:
  name: opus
  namespace: $NAMESPACE
spec:
  llmProvider:
    name: vertex-anthropic
  model: "claude-opus-4-6"
  timeouts:
    analysisSeconds: 300
    executionSeconds: 300
    verificationSeconds: 300
---
apiVersion: agentic.openshift.io/v1alpha1
kind: LLMProvider
metadata:
  name: vertex-google
  namespace: $NAMESPACE
spec:
  type: GoogleCloudVertex
  googleCloudVertex:
    projectID: $VERTEX_PROJECT_ID
    region: global
    modelProvider: Google
    credentialsSecret:
      name: llm-creds-vertex
---
apiVersion: agentic.openshift.io/v1alpha1
kind: Agent
metadata:
  name: gemini
  namespace: $NAMESPACE
spec:
  llmProvider:
    name: vertex-google
  model: "gemini-2.5-pro"
  timeouts:
    analysisSeconds: 300
    executionSeconds: 300
    verificationSeconds: 300
EOF
    echo "    Vertex AI providers configured (Anthropic + Gemini)."
}

function run_evals() {
    echo "==> Running agentic evaluations..."
    cd "$AGENTIC_DIR"
    make setup

    if [[ -n "${SUITES:-}" ]]; then
        make evals SUITES="$SUITES"
    else
        make evals
    fi
}

function collect_results() {
    echo "==> Collecting results to ${ARTIFACT_DIR}..."
    mkdir -p "$ARTIFACT_DIR/agentic-results"
    cp -r "$AGENTIC_DIR/results/"* "$ARTIFACT_DIR/agentic-results/" 2>/dev/null || true
}

function cleanup() {
    echo "==> Cleaning up..."
    cd "$AGENTIC_DIR"
    make cleanup || true
}

trap cleanup EXIT

install_operator

echo "==> Configuring LLM providers..."
setup_openai
setup_vertex

run_evals
collect_results

echo "==> Agentic evaluation complete."
