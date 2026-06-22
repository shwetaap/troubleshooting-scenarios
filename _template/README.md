# <Team Name> Evaluation Scenarios

<!-- Describe what your eval suite tests -->

## Prerequisites

- OpenShift cluster accessible via `oc`
- `OPENAI_API_KEY` exported (for OLS credentials and judge LLM)

## Scenarios

| Tag | Description |
|-----|-------------|
| `_example_scenario` | Example — replace with your own |

## Usage

```bash
export OPENAI_API_KEY=<your-key>
make setup     # install OLS + MCP + suite dependencies
make evals     # run all scenarios
make teardown   # remove suite dependencies + MCP
```

Run a single scenario:

```bash
make _example_scenario-eval
```

Results are written to `results/`.
