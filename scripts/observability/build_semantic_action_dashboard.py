#!/usr/bin/env python3
"""Build semantic-action observability metrics and a Markdown dashboard."""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB_PATH = REPO_ROOT / "data/semantic-actions/semantic-actions.sqlite"
DEFAULT_CONFIG_PATH = REPO_ROOT / "config/semantic-action-observability.v0.json"
DEFAULT_OUTPUT_PATH = REPO_ROOT / "data/reports/semantic-action-observability/metrics-summary.json"
DEFAULT_DASHBOARD_PATH = REPO_ROOT / "data/reports/semantic-action-observability/dashboard.md"
SUMMARY_SCHEMA_VERSION = "openstaff.semantic-action-observability-summary.v0"

SELECTOR_ACTION_TYPES = {"switch_app", "focus_window", "click", "type", "drag"}
MIS_TRIGGER_ERROR_CODES = {
    "contextMismatchCount": "SEM202-CONTEXT-MISMATCH",
    "postAssertionFailureCount": "SEM203-ASSERTION-FAILED",
    "coordinateFallbackAttemptCount": "SEM201-COORDINATE-FALLBACK-DISALLOWED",
}
MIS_TRIGGER_ALERT_METADATA = {
    "contextMismatchCount": {
        "severity": "critical",
        "message": "前置上下文校验在错误 app/window/url 上拦截了潜在误触发。",
    },
    "postAssertionFailureCount": {
        "severity": "critical",
        "message": "执行后断言失败，说明动作可能已经触发到错误上下文或 UI 已发生漂移。",
    },
    "coordinateFallbackAttemptCount": {
        "severity": "warning",
        "message": "语义解析退化到坐标 fallback，说明当前 selector 命中质量不足。",
    },
}


class SemanticObservabilityError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Aggregate semantic-action execution metrics into a dashboard."
    )
    parser.add_argument(
        "--db-path",
        action="append",
        type=Path,
        help=(
            "Semantic action SQLite DB path. Can be repeated. "
            "When omitted, defaults to data/semantic-actions/semantic-actions.sqlite."
        ),
    )
    parser.add_argument(
        "--source",
        action="append",
        default=[],
        help="Explicit environment-scoped source in ENV=PATH format. Can be repeated.",
    )
    parser.add_argument(
        "--environment",
        type=str,
        help="Fallback environment label for --db-path rows when execution logs do not embed one.",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG_PATH,
        help=f"Observability config JSON path (default: {DEFAULT_CONFIG_PATH}).",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT_PATH,
        help=f"Metrics summary JSON output path (default: {DEFAULT_OUTPUT_PATH}).",
    )
    parser.add_argument(
        "--dashboard-output",
        type=Path,
        default=DEFAULT_DASHBOARD_PATH,
        help=f"Markdown dashboard output path (default: {DEFAULT_DASHBOARD_PATH}).",
    )
    parser.add_argument(
        "--check-gates",
        action="store_true",
        help="Exit non-zero when one or more configured gates fail.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print the structured summary JSON to stdout.",
    )
    return parser.parse_args()


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def repo_relative(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(resolved)


def read_json(path: Path) -> Any:
    if not path.exists():
        raise SemanticObservabilityError(f"JSON file does not exist: {path}")
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def rounded_rate(numerator: int, denominator: int) -> float | None:
    if denominator == 0:
        return None
    return round(numerator / denominator, 4)


def normalize_environment(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    candidate = value.strip().lower()
    return candidate or None


def parse_json_text(value: str | None, default: Any) -> Any:
    if value is None or value == "":
        return default
    try:
        return json.loads(value)
    except json.JSONDecodeError as exc:
        raise SemanticObservabilityError(f"Invalid JSON payload in SQLite row: {exc}") from exc


def normalize_selector_token(value: str) -> str:
    token = value.split(":", 1)[-1].strip()
    return token or value


def parse_source(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise SemanticObservabilityError(
            f"Invalid --source value {value!r}; expected ENV=PATH."
        )
    environment, raw_path = value.split("=", 1)
    normalized_environment = normalize_environment(environment)
    if normalized_environment is None:
        raise SemanticObservabilityError(
            f"Invalid --source value {value!r}; environment must be non-empty."
        )
    if not raw_path.strip():
        raise SemanticObservabilityError(
            f"Invalid --source value {value!r}; path must be non-empty."
        )
    return normalized_environment, Path(raw_path).resolve()


def resolve_sources(args: argparse.Namespace, config: dict[str, Any]) -> list[dict[str, Any]]:
    sources: list[dict[str, Any]] = []
    for source in args.source:
        environment, db_path = parse_source(source)
        sources.append(
            {
                "dbPath": db_path,
                "explicitEnvironment": environment,
            }
        )

    db_paths = [path.resolve() for path in (args.db_path or [])]
    if not sources and not db_paths:
        db_paths = [DEFAULT_DB_PATH.resolve()]

    fallback_environment = normalize_environment(args.environment)
    for db_path in db_paths:
        sources.append(
            {
                "dbPath": db_path,
                "explicitEnvironment": fallback_environment,
            }
        )

    if not sources:
        raise SemanticObservabilityError("No semantic-action metric sources were provided.")

    return sources


def load_records(
    sources: list[dict[str, Any]],
    config: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    records: list[dict[str, Any]] = []
    resolved_sources: list[dict[str, Any]] = []
    fallback_environment = normalize_environment(config.get("defaultEnvironment")) or "dev"

    for source in sources:
        db_path = Path(source["dbPath"]).resolve()
        explicit_environment = source.get("explicitEnvironment")
        if not db_path.exists():
            raise SemanticObservabilityError(f"Semantic action DB does not exist: {db_path}")

        resolved_sources.append(
            {
                "dbPath": repo_relative(db_path),
                "environment": explicit_environment,
            }
        )

        connection = sqlite3.connect(db_path)
        connection.row_factory = sqlite3.Row
        try:
            rows = connection.execute(
                """
                SELECT
                    actions.action_id,
                    actions.session_id,
                    actions.action_type,
                    actions.manual_review_required,
                    actions.context_json,
                    execution_logs.execution_log_id,
                    execution_logs.status AS execution_status,
                    execution_logs.error_code,
                    execution_logs.selector_hit_path_json,
                    execution_logs.result_json,
                    execution_logs.duration_ms,
                    execution_logs.executed_at
                FROM action_execution_logs AS execution_logs
                INNER JOIN semantic_actions AS actions
                    ON actions.action_id = execution_logs.action_id
                ORDER BY execution_logs.executed_at ASC, execution_logs.execution_log_id ASC
                """
            ).fetchall()
        except sqlite3.Error as exc:
            raise SemanticObservabilityError(
                f"Failed to read semantic-action metrics from {db_path}: {exc}"
            ) from exc
        finally:
            connection.close()

        for row in rows:
            result = parse_json_text(row["result_json"], {})
            context = parse_json_text(row["context_json"], {})
            selector_hit_path = parse_json_text(row["selector_hit_path_json"], [])
            teacher_confirmation = result.get("teacherConfirmation") if isinstance(result, dict) else {}
            context_guard = result.get("contextGuard") if isinstance(result, dict) else {}
            post_assertions = result.get("postAssertions") if isinstance(result, dict) else {}

            environment = (
                explicit_environment
                or normalize_environment(result.get("environment"))
                or normalize_environment(context.get("environment"))
                or fallback_environment
            )

            records.append(
                {
                    "environment": environment,
                    "dbPath": repo_relative(db_path),
                    "actionId": row["action_id"],
                    "sessionId": row["session_id"],
                    "executionLogId": row["execution_log_id"],
                    "actionType": result.get("actionType") or row["action_type"],
                    "status": result.get("status") or row["execution_status"],
                    "rawStatus": row["execution_status"],
                    "dryRun": bool(result.get("dryRun")) or "DRY_RUN" in (row["execution_status"] or ""),
                    "matchedLocatorType": result.get("matchedLocatorType"),
                    "selectorHitPath": [
                        item for item in selector_hit_path if isinstance(item, str) and item.strip()
                    ],
                    "errorCode": result.get("errorCode") or row["error_code"],
                    "durationMs": int(row["duration_ms"] or 0),
                    "executedAt": row["executed_at"],
                    "manualReviewRequired": bool(row["manual_review_required"]),
                    "teacherConfirmationStatus": (
                        teacher_confirmation.get("status")
                        if isinstance(teacher_confirmation, dict)
                        else None
                    ),
                    "contextGuardStatus": (
                        context_guard.get("status") if isinstance(context_guard, dict) else None
                    ),
                    "postAssertionsStatus": (
                        post_assertions.get("status") if isinstance(post_assertions, dict) else None
                    ),
                }
            )

    return records, resolved_sources


def selector_eligible(record: dict[str, Any]) -> bool:
    if record["actionType"] not in SELECTOR_ACTION_TYPES:
        return False
    if record.get("contextGuardStatus") == "blocked":
        return False
    if record.get("teacherConfirmationStatus") == "required":
        return False
    return True


def selector_hit(record: dict[str, Any]) -> bool:
    locator_type = record.get("matchedLocatorType")
    return isinstance(locator_type, str) and locator_type != "coordinateFallback"


def build_metrics(records: list[dict[str, Any]]) -> dict[str, Any]:
    total_logs = len(records)
    dry_run_logs = [record for record in records if record["dryRun"]]
    live_logs = [record for record in records if not record["dryRun"]]
    selector_candidates = [record for record in records if selector_eligible(record)]
    selector_hits = [record for record in selector_candidates if selector_hit(record)]
    fallback_counter = Counter(
        str(record["matchedLocatorType"])
        for record in selector_hits
        if isinstance(record.get("matchedLocatorType"), str)
    )
    intercepts = [record for record in records if record["status"] == "blocked"]
    intercept_reasons = Counter(record["errorCode"] or "unknown" for record in intercepts)
    replay_sample = live_logs if live_logs else records
    replay_successes = [record for record in replay_sample if record["status"] == "succeeded"]
    teacher_confirmation_records = [
        record
        for record in records
        if record.get("teacherConfirmationStatus") in {"required", "approved"}
    ]
    teacher_confirmation_status_counts = Counter(
        record["teacherConfirmationStatus"] for record in teacher_confirmation_records
    )

    mis_trigger_records_by_bucket: dict[str, list[dict[str, Any]]] = {}
    for metric_name, error_code in MIS_TRIGGER_ERROR_CODES.items():
        mis_trigger_records_by_bucket[metric_name] = [
            record for record in records if record.get("errorCode") == error_code
        ]
    mis_trigger_keys = {
        record["executionLogId"]
        for bucket in mis_trigger_records_by_bucket.values()
        for record in bucket
    }

    return {
        "executionLogCount": {
            "value": total_logs,
            "reason": "Total semantic-action execution logs included in this dashboard slice.",
        },
        "liveExecutionCount": {
            "value": len(live_logs),
            "reason": "Execution logs produced by non-dry-run semantic execution attempts.",
        },
        "dryRunExecutionCount": {
            "value": len(dry_run_logs),
            "reason": "Execution logs produced by dry-run semantic execution attempts.",
        },
        "selectorHitRate": {
            "value": rounded_rate(len(selector_hits), len(selector_candidates)),
            "numerator": len(selector_hits),
            "denominator": len(selector_candidates),
            "hitActionIds": sorted({record["actionId"] for record in selector_hits}),
            "missedActionIds": sorted(
                {record["actionId"] for record in selector_candidates if not selector_hit(record)}
            ),
            "reason": (
                "Selector-capable actions that reached resolver execution and still matched a "
                "non-coordinate semantic locator."
            ),
        },
        "fallbackLayerDistribution": {
            "value": None,
            "totalMatchedExecutions": len(selector_hits),
            "counts": dict(sorted(fallback_counter.items())),
            "reason": (
                "Distribution of the final semantic locator layer that actually resolved the action "
                "(for example axPath, roleAndTitle, textAnchor, imageAnchor)."
            ),
        },
        "interceptRate": {
            "value": rounded_rate(len(intercepts), total_logs),
            "numerator": len(intercepts),
            "denominator": total_logs,
            "blockedActionIds": sorted({record["actionId"] for record in intercepts}),
            "reasonCounts": dict(sorted(intercept_reasons.items())),
            "reason": "Semantic actions that were blocked before or during execution by safety/quality guards.",
        },
        "replaySuccessRate": {
            "value": rounded_rate(len(replay_successes), len(replay_sample)),
            "numerator": len(replay_successes),
            "denominator": len(replay_sample),
            "mode": "live_only" if live_logs else "all_runs",
            "successfulActionIds": sorted({record["actionId"] for record in replay_successes}),
            "failedActionIds": sorted(
                {record["actionId"] for record in replay_sample if record["status"] != "succeeded"}
            ),
            "reason": (
                "Successful semantic replays across live executions when present; otherwise all runs "
                "are used as a fallback sample."
            ),
        },
        "manualConfirmationRate": {
            "value": rounded_rate(len(teacher_confirmation_records), total_logs),
            "numerator": len(teacher_confirmation_records),
            "denominator": total_logs,
            "statusCounts": dict(sorted(teacher_confirmation_status_counts.items())),
            "actionIds": sorted({record["actionId"] for record in teacher_confirmation_records}),
            "reason": "Actions that required or consumed teacher confirmation during execution.",
        },
        "misTriggerRiskEventCount": {
            "value": len(mis_trigger_keys),
            "breakdown": {
                metric_name: len(bucket_records)
                for metric_name, bucket_records in sorted(mis_trigger_records_by_bucket.items())
            },
            "actionIds": sorted(
                {
                    record["actionId"]
                    for bucket_records in mis_trigger_records_by_bucket.values()
                    for record in bucket_records
                }
            ),
            "reason": (
                "Potential mis-trigger risk events, including context mismatches, post-assertion "
                "failures, and semantic execution attempts that degraded to coordinate fallback."
            ),
        },
    }


def metric_value(metrics: dict[str, Any], name: str) -> float | int | None:
    payload = metrics.get(name)
    if not isinstance(payload, dict):
        return None
    return payload.get("value")


def evaluate_gate_set(metrics: dict[str, Any], gate_config: dict[str, Any]) -> dict[str, Any]:
    results = []
    for metric_name, gate in sorted(gate_config.items()):
        actual = metric_value(metrics, metric_name)
        gate_type = gate.get("type")
        result = {
            "metric": metric_name,
            "type": gate_type,
            "actual": actual,
            "passed": None,
            "skipped": False,
        }

        if actual is None:
            result["skipped"] = True
            result["reason"] = "Metric is unavailable for the selected sample."
            results.append(result)
            continue

        if gate_type == "minimum":
            threshold = gate.get("value")
            result["threshold"] = threshold
            result["operator"] = ">="
            result["passed"] = actual >= threshold
        elif gate_type == "maximum":
            threshold = gate.get("value")
            result["threshold"] = threshold
            result["operator"] = "<="
            result["passed"] = actual <= threshold
        else:
            raise SemanticObservabilityError(
                f"Unsupported gate type for {metric_name}: {gate_type}"
            )

        results.append(result)

    failed = [item for item in results if item.get("passed") is False]
    skipped = [item for item in results if item.get("skipped")]
    return {
        "passed": len(failed) == 0,
        "total": len(results),
        "failed": len(failed),
        "skipped": len(skipped),
        "results": results,
    }


def build_alerts(
    overall_metrics: dict[str, Any],
    environment_metrics: dict[str, dict[str, Any]],
    gates: dict[str, Any],
) -> list[dict[str, Any]]:
    alerts: list[dict[str, Any]] = []

    for environment, metrics in sorted(environment_metrics.items()):
        breakdown = (metrics.get("misTriggerRiskEventCount") or {}).get("breakdown") or {}
        for metric_name, metadata in MIS_TRIGGER_ALERT_METADATA.items():
            count = int(breakdown.get(metric_name, 0) or 0)
            if count <= 0:
                continue
            alerts.append(
                {
                    "kind": "misTriggerRisk",
                    "environment": environment,
                    "metric": metric_name,
                    "severity": metadata["severity"],
                    "count": count,
                    "message": metadata["message"],
                }
            )

    overall_failed = [
        result for result in gates["overall"]["results"] if result.get("passed") is False
    ]
    for result in overall_failed:
        alerts.append(
            {
                "kind": "gateFailure",
                "environment": "overall",
                "metric": result["metric"],
                "severity": "warning",
                "count": 1,
                "message": (
                    f"Overall metric {result['metric']} violated gate: actual={result['actual']} "
                    f"{result['operator']} threshold={result['threshold']}."
                ),
            }
        )

    for environment, payload in sorted(gates["perEnvironment"].items()):
        for result in payload["results"]:
            if result.get("passed") is not False:
                continue
            alerts.append(
                {
                    "kind": "gateFailure",
                    "environment": environment,
                    "metric": result["metric"],
                    "severity": "warning",
                    "count": 1,
                    "message": (
                        f"Environment metric {result['metric']} violated gate: actual={result['actual']} "
                        f"{result['operator']} threshold={result['threshold']}."
                    ),
                }
            )

    overall_breakdown = (overall_metrics.get("misTriggerRiskEventCount") or {}).get("breakdown") or {}
    if sum(int(value or 0) for value in overall_breakdown.values()) > 0:
        alerts.append(
            {
                "kind": "summary",
                "environment": "overall",
                "metric": "misTriggerRiskEventCount",
                "severity": "critical",
                "count": int(
                    (overall_metrics.get("misTriggerRiskEventCount") or {}).get("value") or 0
                ),
                "message": "Detected one or more mis-trigger risk events; teacher review is required.",
            }
        )

    return alerts


def build_summary(
    *,
    records: list[dict[str, Any]],
    resolved_sources: list[dict[str, Any]],
    config: dict[str, Any],
    config_path: Path,
    output_path: Path,
    dashboard_path: Path,
) -> dict[str, Any]:
    expected_environments = [
        environment
        for environment in (
            normalize_environment(value) for value in config.get("expectedEnvironments", [])
        )
        if environment is not None
    ]
    observed_environments = sorted(
        {record["environment"] for record in records if normalize_environment(record["environment"])}
    )
    all_environments = list(dict.fromkeys(expected_environments + observed_environments))
    if not all_environments:
        all_environments = [normalize_environment(config.get("defaultEnvironment")) or "dev"]

    overall_metrics = build_metrics(records)
    environment_summaries: dict[str, dict[str, Any]] = {}
    for environment in all_environments:
        environment_records = [record for record in records if record["environment"] == environment]
        environment_summaries[environment] = {
            "executionLogCount": len(environment_records),
            "metrics": build_metrics(environment_records),
        }

    overall_gates = evaluate_gate_set(overall_metrics, config.get("gates") or {})
    per_environment_gates = {
        environment: evaluate_gate_set(
            environment_payload["metrics"], config.get("perEnvironmentGates") or {}
        )
        for environment, environment_payload in environment_summaries.items()
    }
    gates_passed = overall_gates["passed"] and all(
        payload["passed"] for payload in per_environment_gates.values()
    )
    alerts = build_alerts(
        overall_metrics,
        {environment: payload["metrics"] for environment, payload in environment_summaries.items()},
        {
            "overall": overall_gates,
            "perEnvironment": per_environment_gates,
        },
    )

    return {
        "schemaVersion": SUMMARY_SCHEMA_VERSION,
        "generatedAt": now_iso(),
        "configId": config.get("configId"),
        "configPath": repo_relative(config_path.resolve()),
        "outputPath": repo_relative(output_path.resolve()),
        "dashboardPath": repo_relative(dashboard_path.resolve()),
        "sourceCount": len(resolved_sources),
        "sources": resolved_sources,
        "totalExecutionLogs": len(records),
        "metrics": overall_metrics,
        "environments": environment_summaries,
        "gates": {
            "passed": gates_passed,
            "overall": overall_gates,
            "perEnvironment": per_environment_gates,
        },
        "alerts": alerts,
        "notes": [
            "replaySuccessRate prefers live executions; when no live executions exist, it falls back to all runs.",
            "selectorHitRate excludes actions blocked before resolver execution by context guard or teacher confirmation.",
            "misTriggerRiskEventCount is a safety-focused alert metric, not a user-visible product KPI.",
        ],
    }


def format_metric_value(value: float | int | None) -> str:
    if value is None:
        return "-"
    if isinstance(value, float):
        return f"{value:.4f}"
    return str(value)


def format_counts(counter: dict[str, Any]) -> str:
    if not counter:
        return "-"
    return ", ".join(f"{key}={counter[key]}" for key in sorted(counter))


def build_dashboard_markdown(summary: dict[str, Any]) -> str:
    metrics = summary["metrics"]
    lines = [
        "# Semantic Action Observability Dashboard",
        "",
        f"- Generated at: {summary['generatedAt']}",
        f"- Config: `{summary['configPath']}`",
        f"- Total execution logs: {summary['totalExecutionLogs']}",
        f"- Gates: {'PASS' if summary['gates']['passed'] else 'FAIL'}",
        "",
        "## Sources",
    ]
    if summary["sources"]:
        for source in summary["sources"]:
            environment = source.get("environment") or "per-log"
            lines.append(f"- `{environment}` -> `{source['dbPath']}`")
    else:
        lines.append("- No sources.")

    lines.extend(
        [
            "",
            "## Overall",
            "",
            "| Metric | Value | Detail |",
            "| --- | --- | --- |",
            (
                f"| selectorHitRate | {format_metric_value(metrics['selectorHitRate']['value'])} | "
                f"{metrics['selectorHitRate']['numerator']}/{metrics['selectorHitRate']['denominator']} |"
            ),
            (
                f"| replaySuccessRate | {format_metric_value(metrics['replaySuccessRate']['value'])} | "
                f"{metrics['replaySuccessRate']['numerator']}/{metrics['replaySuccessRate']['denominator']} "
                f"({metrics['replaySuccessRate']['mode']}) |"
            ),
            (
                f"| interceptRate | {format_metric_value(metrics['interceptRate']['value'])} | "
                f"{metrics['interceptRate']['numerator']}/{metrics['interceptRate']['denominator']} |"
            ),
            (
                f"| manualConfirmationRate | {format_metric_value(metrics['manualConfirmationRate']['value'])} | "
                f"{metrics['manualConfirmationRate']['numerator']}/{metrics['manualConfirmationRate']['denominator']} |"
            ),
            (
                f"| misTriggerRiskEventCount | {format_metric_value(metrics['misTriggerRiskEventCount']['value'])} | "
                f"{format_counts(metrics['misTriggerRiskEventCount']['breakdown'])} |"
            ),
            "",
            "## Environment Breakdown",
            "",
            "| Environment | Logs | Selector Hit | Fallback Layers | Intercept | Replay Success | Manual Confirmation | Risk Events |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
    )

    for environment, payload in sorted(summary["environments"].items()):
        env_metrics = payload["metrics"]
        lines.append(
            "| "
            + " | ".join(
                [
                    environment,
                    str(payload["executionLogCount"]),
                    format_metric_value(env_metrics["selectorHitRate"]["value"]),
                    format_counts(env_metrics["fallbackLayerDistribution"]["counts"]),
                    format_metric_value(env_metrics["interceptRate"]["value"]),
                    format_metric_value(env_metrics["replaySuccessRate"]["value"]),
                    format_metric_value(env_metrics["manualConfirmationRate"]["value"]),
                    str(env_metrics["misTriggerRiskEventCount"]["value"]),
                ]
            )
            + " |"
        )

    lines.extend(
        [
            "",
            "## Alerts",
            "",
        ]
    )
    if summary["alerts"]:
        for alert in summary["alerts"]:
            lines.append(
                f"- [{alert['severity']}] `{alert['environment']}` `{alert['metric']}`: {alert['message']}"
            )
    else:
        lines.append("- No active alerts.")

    lines.extend(
        [
            "",
            "## Intercept Reasons",
            "",
            "| Environment | Reasons |",
            "| --- | --- |",
        ]
    )
    for environment, payload in sorted(summary["environments"].items()):
        reason_counts = payload["metrics"]["interceptRate"]["reasonCounts"]
        lines.append(f"| {environment} | {format_counts(reason_counts)} |")

    return "\n".join(lines) + "\n"


def print_summary(summary: dict[str, Any]) -> None:
    metrics = summary["metrics"]
    print(
        "Semantic action dashboard finished. "
        f"gates={'PASS' if summary['gates']['passed'] else 'FAIL'} "
        f"alerts={len(summary['alerts'])} "
        f"output={summary['outputPath']} "
        f"dashboard={summary['dashboardPath']}"
    )
    print(f"selectorHitRate={metrics['selectorHitRate']['value']}")
    print(f"replaySuccessRate={metrics['replaySuccessRate']['value']}")
    print(f"interceptRate={metrics['interceptRate']['value']}")
    print(f"manualConfirmationRate={metrics['manualConfirmationRate']['value']}")
    print(f"misTriggerRiskEventCount={metrics['misTriggerRiskEventCount']['value']}")


def main() -> int:
    args = parse_args()
    config_path = args.config.resolve()
    config = read_json(config_path)
    sources = resolve_sources(args, config)
    records, resolved_sources = load_records(sources, config)
    output_path = args.output.resolve()
    dashboard_path = args.dashboard_output.resolve()

    summary = build_summary(
        records=records,
        resolved_sources=resolved_sources,
        config=config,
        config_path=config_path,
        output_path=output_path,
        dashboard_path=dashboard_path,
    )
    write_json(output_path, summary)
    write_text(dashboard_path, build_dashboard_markdown(summary))

    if args.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        print_summary(summary)

    if args.check_gates and not summary["gates"]["passed"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
