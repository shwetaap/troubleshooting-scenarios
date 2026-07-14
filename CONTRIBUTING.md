# Adding a New Eval Suite

Each eval suite owns a top-level directory containing evaluation scenarios for a domain. This guide explains how to create one.

## Naming conventions

Directory names must use underscores (`_`), not hyphens (`-`). This keeps directory names consistent with scenario tags and avoids character translation at runtime.

## 1. Copy the template

```bash
cp -r _template my_suite
cd my_suite
```

## 2. Directory structure

```
my_suite/
├── Makefile                    # Declares scenarios, MCP config, setup/cleanup
├── system.yaml                 # Evaluation framework config (judge model, metrics)
├── evals.yaml                  # Conversation definitions (queries + expected responses)
├── README.md                   # Team documentation
├── build/                      # Optional: suite-specific setup scripts, operator CRs
├── my_scenario/
│   ├── setup.sh                # Runs before the conversation starts
│   ├── cleanup.sh              # Runs after the conversation ends
│   └── fixtures/
│       └── manifest.yaml       # Kubernetes manifests deployed by setup.sh
├── another_scenario/
│   └── ...
└── results/                    # Eval output (gitignored)
```

## 3. Define scenarios

### evals.yaml

Each scenario is a conversation with one or more turns. The `tag` field must match the name in the `SCENARIOS` variable in your Makefile.

```yaml
- conversation_group_id: my_scenario
  tag: my_scenario
  description: "What this scenario tests"

  turns:
    - turn_id: investigate
      query: >
        The question sent to OLS.
      expected_response: >
        What a correct answer looks like. The judge LLM scores
        the actual OLS response against this.
      turn_metrics:
        - custom:answer_correctness

  setup_script: ./my_scenario/setup.sh
  cleanup_script: ./my_scenario/cleanup.sh
```

### Scenario setup/cleanup scripts

- `setup.sh` runs before the conversation — deploy workloads, inject faults, wait for signals
- `cleanup.sh` runs after — delete namespaces, remove fixtures
- Both must be executable (`chmod +x`)
- Use `oc apply -f fixtures/manifest.yaml` for Kubernetes resources

### system.yaml

Configures the evaluation framework. Key fields:

- `llm.model` — judge LLM that scores responses (e.g., `gpt-4o-mini`)
- `api.model` — model OLS uses to answer queries (must exist in OLSConfig)
- `api.api_base` — placeholder, replaced at runtime with `OLS_URL`
- `metrics_metadata` — which metrics to evaluate per turn/conversation

## 4. Configure the Makefile

```makefile
SCENARIOS = my_scenario another_scenario
MCP_TOOLSETS = core,config,my_toolset

include ../scripts/eval.mk

.PHONY: setup
setup: _setup-shared
	# Team-specific cluster setup (operator install, CR apply, etc.)

.PHONY: cleanup
cleanup:
	# Team-specific cleanup
	$(MAKE) _cleanup-shared
```

### Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SCENARIOS` | (required) | Space-separated scenario tags |
| `MCP_TOOLSETS` | `core,config` | MCP server toolsets |
| `MCP_IMAGE` | openshift-mcp-server | MCP container image |
| `MCP_KIALI_URL` | (empty) | Set for ossm toolset |
| `OLS_URL` | `https://localhost:8443` | Override to use cluster Route |

### Targets provided by eval.mk

| Target | Description |
|--------|-------------|
| `_setup-shared` | venv + preflight + OLS install + MCP deploy + OLS connect |
| `_cleanup-shared` | OLS disconnect + MCP cleanup |
| `evals` | Run all scenarios |
| `<tag>-eval` | Run a single scenario |
| `help` | List available targets |

## 5. Test

```bash
export OPENAI_API_KEY=<your-key>
make setup
make evals
make cleanup
```

## 6. Shared scripts reference

All shared scripts live in `scripts/` at the repo root. Teams should not need to modify them.

| Script | Purpose |
|--------|---------|
| `setup-venv.sh` | Create venv with lightspeed-eval (idempotent) |
| `setup-ols.sh` | Install OLS operator + OLSConfig (idempotent) |
| `cleanup-ols.sh` | Remove OLS operator |
| `setup-mcp.sh` | Deploy MCP server |
| `cleanup-mcp.sh` | Remove MCP server |
| `connect-ols-mcp.sh` | Register MCP in OLSConfig + restart |
| `disconnect-ols-mcp.sh` | Remove MCP from OLSConfig + restart |
| `preflight.sh` | Check cluster + OLS readiness |
| `run-evals.sh` | Port-forward + lightspeed-eval + cleanup |
| `mcp-config.sh` | Build MCP config.toml ConfigMap |
