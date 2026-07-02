# RHOAI Test Infrastructure for troubleshooting-scenarios

Provisions Red Hat OpenShift AI (RHOAI) operators, GPU infrastructure, and a
vLLM model-serving endpoint for testing troubleshooting scenarios against a
self-hosted Llama-3.1-8B-Instruct model instead of external hosted APIs.

## When to use

Set `RHOAI_PROVISION=true` in the CI job environment (or export it locally)
before running `tests/scripts/test-troubleshooting-scenarios-rhoai.sh`. When
the flag is unset or `false`, the script skips RHOAI provisioning.

## Required environment variables

| Variable | Purpose |
|---|---|
| `RHOAI_PROVISION` | Set to `true` to enable RHOAI provisioning |
| `HUGGING_FACE_HUB_TOKEN` | HuggingFace token to download Llama 3.1 8B model weights. Works with any HuggingFace-hosted model. Larger models may require scaling GPU nodes (more GPUs, higher VRAM) |
| `VLLM_API_KEY` | Arbitrary value — we define it ourselves. The same value is set as the vLLM endpoint secret and can be used for authenticating requests |
| `OPENAI_API_KEY` (optional) | For judge LLM if using the evaluation framework |

## Cluster prerequisites

- OpenShift 4.21+ cluster with GPU-capable nodes (e.g. AWS `g4dn`, `g5`, `p3`, `p4` instance types)
- OLM (Operator Lifecycle Manager) available — the bootstrap installs RHODS, NVIDIA GPU Operator, and NFD Operator via OLM subscriptions
- `oc` CLI authenticated with cluster-admin privileges

## Script flow

```
test-troubleshooting-scenarios-rhoai.sh (RHOAI_PROVISION=true)
│
├─ 1. Create NFD + NVIDIA namespaces
│     manifests/namespaces/{nfd,nvidia-operator}.yaml
│
├─ 2. scripts/bootstrap.sh
│     Install operator subscriptions (RHODS, GPU Operator, NFD),
│     wait for CSVs to reach Succeeded, create DataScienceCluster
│
├─ 3. scripts/gpu-setup.sh
│     Apply NFD instance + ClusterPolicy, patch tolerations,
│     wait for GPU operator pods healthy + GPU capacity on nodes
│
├─ 4. Create vLLM namespace (troubleshooting-scenarios-rhoai),
│     secrets (HuggingFace token, vLLM API key),
│     and chat-template ConfigMap
│
├─ 5. scripts/fetch-vllm-image.sh
│     Extract vLLM CUDA image from RHOAI ServingRuntime template
│     (falls back to a pinned registry.redhat.io digest)
│
├─ 6. scripts/deploy-vllm.sh
│     Wait for KServe CRDs + controller + webhook, re-verify GPU,
│     apply ServingRuntime + InferenceService manifests
│
├─ 7. scripts/get-vllm-pod-info.sh
│     Wait for the InferenceService pod to reach Running,
│     discover the KSVC_URL (Knative or RawDeployment), write pod.env
│
└─ 8. Run troubleshooting scenario tests against the vLLM endpoint
```

## Runtime expectations

The full provisioning flow takes roughly **30–50 minutes** on a warm cluster,
dominated by:

- Operator CSV installs and reconciliation (~5–10 min)
- GPU operator pod image pulls and NVIDIA driver loading (~10–20 min)
- Llama 3.1 8B model download and vLLM startup (~10–15 min)

On a cold cluster (first GPU workload, no image cache), add another 10–15 min
for image pulls.

## Directory layout

```
tests/rhoai/
├── manifests/
│   ├── gpu/            # NFD instance, NVIDIA ClusterPolicy
│   ├── namespaces/     # NFD and NVIDIA operator namespaces
│   ├── operators/      # OLM subscriptions, OperatorGroups, DataScienceCluster
│   └── vllm/           # ServingRuntime and InferenceService for vLLM
└── scripts/
    ├── bootstrap.sh        # Install and wait for operators
    ├── gpu-setup.sh        # NFD + GPU capacity setup
    ├── fetch-vllm-image.sh # Resolve vLLM container image
    ├── deploy-vllm.sh      # Deploy vLLM via KServe
    └── get-vllm-pod-info.sh# Discover endpoint URL, write pod.env
```

## Usage in CI

The RHOAI provisioning is integrated into OpenShift CI periodic jobs. The CI
job configuration should:

1. Request a GPU-enabled cluster (variant: gpu, region: us-east-2)
2. Set `RHOAI_PROVISION=true`
3. Provide credentials for `HUGGING_FACE_HUB_TOKEN` and `VLLM_API_KEY`
4. Run `tests/scripts/test-troubleshooting-scenarios-rhoai.sh`

Example CI configuration snippet:

```yaml
tests:
- as: troubleshooting-rhoai-periodic
  cluster_claim:
    architecture: amd64
    cloud: aws
    labels:
      region: us-east-2
      variant: gpu
    product: ocp
    version: "4.21"
  cron: 10 8 * * 0  # Weekly on Sunday at 08:10
  steps:
    test:
    - as: rhoai-test
      commands: |
        export RHOAI_PROVISION=true
        export HUGGING_FACE_HUB_TOKEN=$(cat /var/run/huggingface/token)
        export VLLM_API_KEY=$(cat /var/run/vllm/key)
        tests/scripts/test-troubleshooting-scenarios-rhoai.sh
      credentials:
      - mount_path: /var/run/huggingface
        name: huggingface-token
        namespace: test-credentials
      - mount_path: /var/run/vllm
        name: vllm-api-key
        namespace: test-credentials
```

## Local testing

If you have access to an OCP 4.21+ cluster with GPU nodes:

```bash
cd ~/Documents/Work/code/upstream/troubleshooting-scenarios

# Set required environment variables
export HUGGING_FACE_HUB_TOKEN="your-token"
export VLLM_API_KEY="your-api-key"
export RHOAI_PROVISION=true

# Run the test script
./tests/scripts/test-troubleshooting-scenarios-rhoai.sh
```

## What happens after provisioning

After successful provisioning, the following resources are available:

- **Operators installed**: RHODS, NVIDIA GPU Operator, Node Feature Discovery
- **GPU nodes**: NVIDIA drivers loaded, GPU capacity advertised
- **vLLM endpoint**: Llama 3.1 8B model serving at `$KSVC_URL`
- **Namespace**: `troubleshooting-scenarios-rhoai` with all resources
- **Secrets**: HuggingFace token and vLLM API key

The vLLM endpoint provides an OpenAI-compatible API that can be used for:

- Testing AI-assisted troubleshooting with self-hosted models
- Validating RHOAI integration scenarios
- Running troubleshooting scenarios without external API dependencies

## Troubleshooting

### Common issues

**GPU operator installation timeout**
- The bootstrap script has retry logic built-in
- Check GPU node availability in the cluster

**vLLM pod doesn't start**
- Verify GPU nodes are available: `oc get nodes -l nvidia.com/gpu=true`
- Check HuggingFace token is valid
- Review pod logs: `oc logs -n troubleshooting-scenarios-rhoai -l serving.kserve.io/inferenceservice=vllm-llama-3-1-8b`

**Model download takes too long**
- Llama 3.1 8B is ~16GB, expect 10-15 minutes on typical connections
- Check network connectivity from cluster to huggingface.co

**Wrong AWS region**
- GPU variant clusters are only available in `us-east-2`
- Ensure CI config specifies the correct region

## Resource cleanup

The RHOAI provisioning creates cluster-scoped resources (operators, CRDs) and
namespaced resources. To clean up after testing:

```bash
# Delete the vLLM namespace
oc delete namespace troubleshooting-scenarios-rhoai

# Optional: Remove operators (affects entire cluster)
oc delete subscription rhods-operator -n openshift-operators
oc delete subscription gpu-operator-certified -n nvidia-gpu-operator
oc delete subscription nfd -n openshift-nfd
```

**Note**: Operator cleanup should only be done if no other workloads depend on
RHOAI or GPU infrastructure.

## Integration with troubleshooting-scenarios

The RHOAI infrastructure enables testing troubleshooting scenarios with:

1. **Self-hosted AI models**: Use vLLM endpoint instead of external APIs
2. **RHOAI-specific scenarios**: Test troubleshooting of RHOAI components
3. **GPU troubleshooting**: Validate GPU-related issue detection
4. **Air-gapped testing**: No dependency on external AI APIs

Example use cases:

- Test AI-assisted troubleshooting of cluster issues using local models
- Validate troubleshooting scenarios for RHOAI operator failures
- Test detection of GPU driver issues, resource exhaustion, model serving problems

## References

- [RHOAI Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai)
- [vLLM Documentation](https://docs.vllm.ai/)
- [KServe Documentation](https://kserve.github.io/website/)
- [OpenShift CI Documentation](https://docs.ci.openshift.org/)
- [lightspeed-service RHOAI implementation](https://github.com/openshift/lightspeed-service/pull/2946)
