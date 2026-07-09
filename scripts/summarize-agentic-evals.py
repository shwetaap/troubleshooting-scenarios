#!/usr/bin/env python3
"""Parse lightspeed-eval summary JSON files and generate a summary table."""

import csv
import json
import sys
from pathlib import Path

import yaml

METRIC_LABELS = {
    "custom:proposal_status": "Status",
    "custom:proposal_evaluation_correctness": "Correctness",
}

GREEN = "\033[0;32m"
RED = "\033[0;31m"
RESET = "\033[0m"


def load_json_data(json_files: list[Path]) -> tuple[list[list[dict]], dict]:
    """Load results and configuration from JSON summary files."""
    runs = []
    config = {}
    for path in sorted(json_files):
        with open(path) as f:
            data = json.load(f)
        runs.append(data.get("results", []))
        if not config:
            config = data.get("configuration", {})
    return runs, config


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

    total = len(runs)
    rows = []
    for cid in conversations:
        row = {}
        for mid in metrics:
            passed = sum(1 for r in runs if metric_passed(r, cid, mid))
            row[metric_label(mid)] = (passed, total)
        overall = sum(1 for r in runs if all_passed(r, cid, metrics))
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

        for run_idx, (json_results, csv_rows) in enumerate(zip(json_runs, csv_runs), 1):
            run_metrics = [r for r in json_results if r["conversation_group_id"] == cid]

            lines.append(f"### Run {run_idx}")
            lines.append("")

            # Get response from CSV (same for all metrics in a turn)
            response = None
            for row in csv_rows:
                if row["conversation_group_id"] == cid and row.get("response"):
                    response = row["response"]
                    break

            if response:
                lines.append("<details>")
                lines.append("<summary>Response</summary>")
                lines.append("")
                lines.append(response.strip())
                lines.append("")
                lines.append("</details>")
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

        lines.append("---")
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
        f"- **Temperature**: {llm.get('temperature', 'N/A')}",
        f"- **Max tokens**: {llm.get('max_tokens', 'N/A')}",
        "",
    ]
    return "\n".join(lines)


def format_cell(value) -> str:
    if isinstance(value, tuple):
        return md_cell(value[0], value[1])
    return str(value)


def generate_markdown(
    conversations: list[str],
    columns: list[str],
    rows: list[dict],
    total_runs: int,
    json_runs: list[list[dict]],
    csv_runs: list[list[dict]],
    config: dict,
    descriptions: dict[str, str],
) -> str:
    header = "| Conversation | " + " | ".join(columns) + " |"
    separator = "|---|" + "|".join("---" for _ in columns) + "|"
    lines = [f"# Evaluation Summary ({total_runs} runs)", "", header, separator]
    for cid, row in zip(conversations, rows):
        cells = " | ".join(format_cell(row[c]) for c in columns)
        lines.append(f"| {cid} | {cells} |")
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

    col_widths = [max(len("Conversation"), *(len(c) for c in conversations))]
    for col in columns:
        values = [cell_display(row[col]) for row in rows]
        col_widths.append(max(len(col), *(len(v) for v in values)))

    sep = "+-" + "-+-".join("-" * w for w in col_widths) + "-+"
    header = "| " + " | ".join(
        f"{h:<{w}}" for h, w in zip(["Conversation"] + columns, col_widths)
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


def load_descriptions(evals_file: Path) -> dict[str, str]:
    """Load conversation descriptions from evals.yaml."""
    if not evals_file.exists():
        return {}
    with open(evals_file) as f:
        data = yaml.safe_load(f)
    if not isinstance(data, list):
        return {}
    return {
        entry["conversation_group_id"]: entry.get("description", "")
        for entry in data
        if "conversation_group_id" in entry
    }


def main():
    if len(sys.argv) < 4:
        print(f"Usage: {sys.argv[0]} RESULTS_DIR EVALS_YAML JSON_FILE [JSON_FILE ...]")
        sys.exit(1)

    results_dir = Path(sys.argv[1])
    evals_file = Path(sys.argv[2])
    json_files = [Path(f) for f in sys.argv[3:]]

    descriptions = load_descriptions(evals_file)
    json_runs, config = load_json_data(json_files)
    csv_runs = load_csv_data(json_files)
    conversations, columns, rows = build_summary(json_runs)
    total_runs = len(json_runs)

    output = results_dir / "summary.md"
    output.write_text(
        generate_markdown(
            conversations, columns, rows, total_runs, json_runs, csv_runs, config,
            descriptions,
        )
    )

    print()
    print_table(conversations, columns, rows)
    print()
    print(f"Summary written to {output}")


if __name__ == "__main__":
    main()
