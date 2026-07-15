#!/usr/bin/env python3
"""Parse lightspeed-eval summary JSON files and generate a summary table."""

import csv
import json
import sys
from datetime import datetime
from pathlib import Path

import yaml

METRIC_LABELS = {
    "custom:proposal_status": "Completed",
    "custom:proposal_evaluation_correctness": "Correctness",
}

GREEN = "\033[0;32m"
RED = "\033[0;31m"
RESET = "\033[0m"


def load_json_data(json_files: list[Path]) -> tuple[list[list[dict]], dict, str]:
    """Load results, configuration, and timestamp from JSON summary files."""
    runs = []
    config = {}
    timestamp = ""
    for path in sorted(json_files):
        with open(path) as f:
            data = json.load(f)
        runs.append(data.get("results", []))
        if not config:
            config = data.get("configuration", {})
            timestamp = data.get("timestamp", "")
    return runs, config, timestamp


def load_csv_data(json_files: list[Path]) -> list[list[dict]]:
    """Load CSV data paired with each JSON file (same timestamp prefix)."""
    runs = []
    for json_path in sorted(json_files):
        csv_path = Path(str(json_path).replace("_summary.json", "_detailed.csv"))
        if csv_path.exists():
            with open(csv_path) as f:
                runs.append(list(csv.DictReader(f)))
        else:
            runs.append([])
    return runs


def metric_label(metric_id: str) -> str:
    return METRIC_LABELS.get(metric_id, metric_id.split(":")[-1])


def metric_passed(results: list[dict], conversation_id: str, metric_id: str) -> bool:
    for r in results:
        if r["conversation_group_id"] == conversation_id and r["metric_identifier"] == metric_id:
            return r["result"] == "PASS"
    return False


def all_passed(results: list[dict], conversation_id: str, metrics: list[str]) -> bool:
    return all(metric_passed(results, conversation_id, m) for m in metrics)


def build_summary(
    runs: list[list[dict]],
) -> tuple[list[str], list[str], list[dict]]:
    """Returns (conversations, columns, rows).

    Each row is a dict with pass/total tuples.
    """
    conversations = []
    seen_convs = set()
    metrics = []
    seen_metrics = set()
    for results in runs:
        for r in results:
            cid = r["conversation_group_id"]
            if cid not in seen_convs:
                seen_convs.add(cid)
                conversations.append(cid)
            mid = r["metric_identifier"]
            if mid not in seen_metrics:
                seen_metrics.add(mid)
                metrics.append(mid)

    rows = []
    for cid in conversations:
        relevant = [r for r in runs if any(x["conversation_group_id"] == cid for x in r)]
        total = len(relevant)
        row = {}
        for mid in metrics:
            passed = sum(1 for r in relevant if metric_passed(r, cid, mid))
            row[metric_label(mid)] = (passed, total)
        overall = sum(1 for r in relevant if all_passed(r, cid, metrics))
        row["Overall"] = (overall, total)
        rows.append(row)

    columns = [metric_label(m) for m in metrics] + ["Overall"]
    return conversations, columns, rows


def md_cell(passed: int, total: int) -> str:
    if passed == total:
        return f"✅ {passed}/{total}"
    if passed == 0:
        return f"❌ {passed}/{total}"
    return f"{passed}/{total}"


def split_model_scenario(cid: str) -> tuple[str, str]:
    """Split 'scenario_model' into (scenario, model) using the last _ segment."""
    parts = cid.rsplit("_", 1)
    if len(parts) == 2:
        return parts[0], parts[1]
    return cid, ""


def generate_pivot_table(
    conversations: list[str],
    rows: list[dict],
) -> str:
    """Build a model-vs-scenario pivot table with Overall results."""
    scenarios = []
    seen_scenarios = set()
    models = []
    seen_models = set()
    pivot = {}

    for cid, row in zip(conversations, rows):
        scenario, model = split_model_scenario(cid)
        if scenario not in seen_scenarios:
            seen_scenarios.add(scenario)
            scenarios.append(scenario)
        if model not in seen_models:
            seen_models.add(model)
            models.append(model)
        pivot[(model, scenario)] = row["Overall"]

    if not models or not scenarios:
        return ""

    header = "| Model | " + " | ".join(scenarios) + " |"
    separator = "|---|" + "|".join("---" for _ in scenarios) + "|"
    lines = [header, separator]
    for model in models:
        cells = []
        for scenario in scenarios:
            value = pivot.get((model, scenario))
            cells.append(format_cell(value) if value else "")
        lines.append(f"| {model} | " + " | ".join(cells) + " |")
    lines.append("")
    return "\n".join(lines)


def generate_details(
    conversations: list[str],
    json_runs: list[list[dict]],
    csv_runs: list[list[dict]],
    descriptions: dict[str, str],
) -> str:
    """Generate per-conversation detail sections with query, responses, and judge results."""
    lines = []

    for cid in conversations:
        lines.append(f"## {cid}")
        lines.append("")

        desc = descriptions.get(cid)
        if desc:
            lines.append(desc)
            lines.append("")

        # Tags and query from first run
        tags = None
        query = None
        for json_results in json_runs:
            for r in json_results:
                if r["conversation_group_id"] == cid and not tags:
                    tags = r.get("tag", [])
                    break
        for csv_rows in csv_runs:
            for row in csv_rows:
                if row["conversation_group_id"] == cid and row.get("query"):
                    query = row["query"]
                    break
            if query:
                break

        if tags:
            lines.append(f"**Tags**: `{'`, `'.join(tags)}`")
            lines.append("")

        if query:
            lines.append("### Query")
            lines.append("")
            lines.append("```")
            lines.append(query.strip())
            lines.append("```")
            lines.append("")

        relevant = [
            (json_results, csv_rows)
            for json_results, csv_rows in zip(json_runs, csv_runs)
            if any(r["conversation_group_id"] == cid for r in json_results)
        ]
        for run_idx, (json_results, csv_rows) in enumerate(relevant, 1):
            run_metrics = [r for r in json_results if r["conversation_group_id"] == cid]

            lines.append(f"### AgenticRun #{run_idx}")
            lines.append("")

            # Metric results from JSON
            for r in run_metrics:
                result_icon = "✅" if r["result"] == "PASS" else "❌"
                score_str = f"{r['score']:.2f}" if r["score"] is not None else "N/A"
                lines.append(
                    f"**{metric_label(r['metric_identifier'])}**: "
                    f"{result_icon} {r['result']} (score: {score_str})"
                )

                if r.get("judge_scores"):
                    for js in r["judge_scores"]:
                        if js.get("reason"):
                            lines.append("")
                            lines.append(f"> {js['reason']}")

                lines.append("")

            # Response from CSV (collapsible, after metrics)
            response = None
            for row in csv_rows:
                if row["conversation_group_id"] == cid and row.get("response"):
                    response = row["response"]
                    break

            if response:
                lines.append("<details>")
                lines.append("<summary>See response</summary>")
                lines.append("")
                lines.append("````markdown")
                lines.append(response.strip())
                lines.append("````")
                lines.append("")
                lines.append("</details>")
                lines.append("")

        lines.append("[Back to top](#evaluation-summary)")
        lines.append("")

    return "\n".join(lines)


def generate_judge_config(config: dict) -> str:
    llm = config.get("llm", {})
    if not llm:
        return ""
    lines = [
        "## Judge LLM",
        "",
        f"- **Provider**: {llm.get('provider', 'N/A')}",
        f"- **Model**: {llm.get('model', 'N/A')}",
        "",
    ]
    return "\n".join(lines)


def format_cell(value) -> str:
    if isinstance(value, tuple):
        return md_cell(value[0], value[1])
    return str(value)


def format_timestamp(timestamp: str) -> str:
    """Format an ISO 8601 timestamp for display."""
    if not timestamp:
        return ""
    dt = datetime.fromisoformat(timestamp)
    return dt.strftime("%Y-%m-%d %H:%M:%S UTC")


def generate_markdown(
    conversations: list[str],
    columns: list[str],
    rows: list[dict],
    total_runs: int,
    json_runs: list[list[dict]],
    csv_runs: list[list[dict]],
    config: dict,
    descriptions: dict[str, str],
    timestamp: str = "",
) -> str:
    header = "| Scenario | " + " | ".join(columns) + " |"
    separator = "|---|" + "|".join("---" for _ in columns) + "|"
    lines = ["# Evaluation Summary"]
    formatted = format_timestamp(timestamp)
    if formatted:
        lines.append(formatted)

    pivot = generate_pivot_table(conversations, rows)
    if pivot:
        lines.extend(["", pivot])

    lines.extend(["## Details", "", header, separator])
    for cid, row in zip(conversations, rows):
        anchor = cid.lower().replace(" ", "-")
        cells = " | ".join(format_cell(row[c]) for c in columns)
        lines.append(f"| [{cid}](#{anchor}) | {cells} |")
    lines.append("")

    judge_config = generate_judge_config(config)
    if judge_config:
        lines.append(judge_config)

    details = generate_details(conversations, json_runs, csv_runs, descriptions)
    lines.append(details)

    return "\n".join(lines)


def colorize(passed: int, total: int) -> str:
    value = f"{passed}/{total}"
    if passed == total:
        return f"{GREEN}{value}{RESET}"
    if passed == 0:
        return f"{RED}{value}{RESET}"
    return value


def cell_display(value) -> str:
    if isinstance(value, tuple):
        return f"{value[0]}/{value[1]}"
    return str(value)


def cell_colored(value) -> str:
    if isinstance(value, tuple):
        return colorize(value[0], value[1])
    return str(value)


def print_table(
    conversations: list[str],
    columns: list[str],
    rows: list[dict],
) -> None:
    if not rows:
        return

    col_widths = [max(len("Scenario"), *(len(c) for c in conversations))]
    for col in columns:
        values = [cell_display(row[col]) for row in rows]
        col_widths.append(max(len(col), *(len(v) for v in values)))

    sep = "+-" + "-+-".join("-" * w for w in col_widths) + "-+"
    header = "| " + " | ".join(
        f"{h:<{w}}" for h, w in zip(["Scenario"] + columns, col_widths)
    ) + " |"

    print(sep)
    print(header)
    print(sep)
    for cid, row in zip(conversations, rows):
        cells = [f"{cid:<{col_widths[0]}}"]
        for i, col in enumerate(columns):
            plain = cell_display(row[col])
            colored = cell_colored(row[col])
            padding = col_widths[i + 1] - len(plain)
            cells.append(f"{colored}{' ' * padding}")
        print("| " + " | ".join(cells) + " |")
    print(sep)


def load_descriptions(evals_files: list[Path]) -> dict[str, str]:
    """Load conversation descriptions from one or more evals YAML files."""
    descriptions = {}
    for evals_file in evals_files:
        if not evals_file.exists():
            continue
        with open(evals_file) as f:
            data = yaml.safe_load(f)
        if not isinstance(data, list):
            continue
        for entry in data:
            if "conversation_group_id" in entry:
                descriptions[entry["conversation_group_id"]] = entry.get("description", "")
    return descriptions


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} RESULTS_DIR [--output FILE] FILE [FILE ...]")
        print("  Files ending in .yaml are treated as evals configs,")
        print("  files ending in .json as summary results.")
        print("  --output FILE  Write summary to FILE instead of RESULTS_DIR/summary.md")
        sys.exit(1)

    args = sys.argv[1:]
    results_dir = Path(args.pop(0))

    output_path = None
    if args and args[0] == "--output":
        args.pop(0)
        output_path = Path(args.pop(0))

    evals_files = [Path(f) for f in args if f.endswith(".yaml")]
    json_files = [Path(f) for f in args if f.endswith(".json")]

    descriptions = load_descriptions(evals_files)
    json_runs, config, timestamp = load_json_data(json_files)
    csv_runs = load_csv_data(json_files)
    conversations, columns, rows = build_summary(json_runs)
    total_runs = len(json_runs)

    output = output_path or results_dir / "summary.md"
    output.write_text(
        generate_markdown(
            conversations, columns, rows, total_runs, json_runs, csv_runs, config,
            descriptions, timestamp,
        )
    )

    print()
    print_table(conversations, columns, rows)
    print()
    print(f"Summary written to {output}")


if __name__ == "__main__":
    main()
