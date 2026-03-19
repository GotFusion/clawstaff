#!/usr/bin/env python3
"""
Aggregate v0 preference-learning metrics and evaluate benchmark gates.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BENCHMARK_ROOT = REPO_ROOT / "data/benchmarks/personal-preference"
DEFAULT_MANIFEST_PATH = DEFAULT_BENCHMARK_ROOT / "manifest.json"
DEFAULT_CONFIG_PATH = DEFAULT_BENCHMARK_ROOT / "metrics-v0.json"
SUMMARY_SCHEMA_VERSION = "openstaff.personal-preference-metrics-summary.v0"


class BenchmarkMetricsError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Aggregate v0 preference-learning metrics from benchmark artifacts."
    )
    parser.add_argument(
        "--benchmark-root",
        type=Path,
        default=DEFAULT_BENCHMARK_ROOT,
        help=f"Benchmark artifact root (default: {DEFAULT_BENCHMARK_ROOT}).",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST_PATH,
        help=f"Benchmark manifest JSON path (default: {DEFAULT_MANIFEST_PATH}).",
    )
    parser.add_argument(
        "--catalog",
        type=Path,
        help="Optional explicit catalog JSON path. Defaults to manifest.catalogPath or <benchmark-root>/catalog.json.",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG_PATH,
        help=f"Metric baseline and gate config JSON path (default: {DEFAULT_CONFIG_PATH}).",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Optional explicit output path. Default: <benchmark-root>/metrics-summary.json",
    )
    parser.add_argument(
        "--check-gates",
        action="store_true",
        help="Exit non-zero when one or more non-skipped gates fail.",
    )
    return parser.parse_args()


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def read_json(path: Path) -> Any:
    if not path.exists():
        raise BenchmarkMetricsError(f"JSON file does not exist: {path}")
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def repo_relative(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(resolved)


def resolve_repo_path(path: str | Path) -> Path:
    candidate = Path(path)
    if candidate.is_absolute():
        return candidate
    return (REPO_ROOT / candidate).resolve()


def resolve_catalog_path(
    manifest: dict[str, Any],
    benchmark_root: Path,
    explicit_catalog_path: Path | None,
) -> Path:
    if explicit_catalog_path is not None:
        return explicit_catalog_path.resolve()

    catalog_path = manifest.get("catalogPath")
    if isinstance(catalog_path, str) and catalog_path.strip():
        resolved = resolve_repo_path(catalog_path)
        if resolved.exists():
            return resolved

    fallback = benchmark_root / "catalog.json"
    if fallback.exists():
        return fallback.resolve()

    raise BenchmarkMetricsError("Unable to resolve benchmark catalog path.")


def merge_generated_case_report(
    report: dict[str, Any],
    benchmark_root: Path,
) -> dict[str, Any]:
    generated_path = benchmark_root / "generated" / report["caseId"] / "case-report.json"
    if not generated_path.exists():
        return report

    generated = read_json(generated_path)
    merged = dict(generated)
    merged.update(report)
    if "measurements" not in merged and "measurements" in generated:
        merged["measurements"] = generated["measurements"]
    return merged


def normalize_reports(
    manifest: dict[str, Any],
    benchmark_root: Path,
) -> list[dict[str, Any]]:
    reports = []
    for report in manifest.get("cases", []):
        if "caseId" not in report:
            raise BenchmarkMetricsError("Benchmark manifest contains a case without caseId.")
        reports.append(merge_generated_case_report(report, benchmark_root))
    if not reports:
        raise BenchmarkMetricsError("Benchmark manifest does not contain any case reports.")
    return reports


def sorted_case_ids(reports: list[dict[str, Any]]) -> list[str]:
    return sorted(report["caseId"] for report in reports)


def rounded_rate(numerator: int, denominator: int) -> float | None:
    if denominator == 0:
        return None
    return round(numerator / denominator, 4)


def build_rate_metric(
    reports: list[dict[str, Any]],
    *,
    predicate,
    reason: str,
) -> dict[str, Any]:
    matched = [report for report in reports if predicate(report)]
    denominator = len(reports)
    numerator = len(matched)
    return {
        "value": rounded_rate(numerator, denominator),
        "numerator": numerator,
        "denominator": denominator,
        "matchedCaseIds": sorted_case_ids(matched),
        "missedCaseIds": sorted_case_ids([report for report in reports if not predicate(report)]),
        "reason": reason,
    }


def list_equal(expected: Any, actual: Any) -> bool:
    if isinstance(expected, list):
        expected = sorted(expected)
    if isinstance(actual, list):
        actual = sorted(actual)
    return expected == actual


def matches_fields(expected: dict[str, Any], actual: dict[str, Any], keys: list[str]) -> bool:
    for key in keys:
        if key not in expected:
            continue
        if not list_equal(expected.get(key), actual.get(key)):
            return False
    return True


def is_safety_intact(report: dict[str, Any]) -> bool:
    if report.get("preferenceCategory") != "risk":
        return True

    expected = report.get("expected") or {}
    actual = report.get("actual") or {}
    module = report.get("module")
    safety_keys_by_module = {
        "assist": ["finalStatus", "selectedKnowledgeItemId", "actionInstruction"],
        "student": ["finalStatus", "selectedKnowledgeItemId", "executionStyle"],
        "review": ["topAction"],
        "repair": ["selectedActionType"],
    }
    return matches_fields(expected, actual, safety_keys_by_module.get(module, []))


def is_quick_feedback_completed(
    report: dict[str, Any],
    supported_actions: set[str],
) -> bool:
    if report.get("module") != "review":
        return False
    actual = report.get("actual") or {}
    action = actual.get("topAction")
    note = (actual.get("suggestedNote") or "").strip()
    return bool(note) and action in supported_actions and bool(report.get("passed"))


def extract_feedback_latency_seconds(
    report: dict[str, Any],
) -> float | None:
    measurements = report.get("measurements") or {}
    value = measurements.get("moduleExecutionDurationSeconds")
    if value is None:
        return None
    try:
        return round(float(value), 4)
    except (TypeError, ValueError):
        raise BenchmarkMetricsError(
            f"Invalid moduleExecutionDurationSeconds in case {report['caseId']}: {value!r}"
        ) from None


def build_latency_metric(review_reports: list[dict[str, Any]]) -> dict[str, Any]:
    samples = []
    missing_case_ids = []
    for report in review_reports:
        latency = extract_feedback_latency_seconds(report)
        if latency is None:
            missing_case_ids.append(report["caseId"])
            continue
        samples.append({"caseId": report["caseId"], "seconds": latency})

    if not samples:
        return {
            "value": None,
            "sampleCount": 0,
            "samples": [],
            "missingCaseIds": sorted(missing_case_ids),
            "reason": "No review latency samples were available in the selected benchmark run.",
        }

    values = [sample["seconds"] for sample in samples]
    return {
        "value": round(float(statistics.median(values)), 4),
        "sampleCount": len(samples),
        "samples": sorted(samples, key=lambda item: item["caseId"]),
        "missingCaseIds": sorted(missing_case_ids),
        "reason": "Median benchmark latency for preference-aware review suggestions.",
    }


def build_capture_policy_metric(
    catalog: dict[str, Any],
    *,
    allowed_source_roots: list[str],
) -> dict[str, Any]:
    normalized_roots = [root.rstrip("/") + "/" for root in allowed_source_roots]
    violating_case_ids: list[str] = []
    violations: list[dict[str, Any]] = []

    for case in catalog.get("cases", []):
        case_violations = []
        for anchor in case.get("sourceAnchors", []):
            relative_path = anchor.get("path", "")
            resolved = resolve_repo_path(relative_path)
            if not any(relative_path.startswith(root) for root in normalized_roots):
                case_violations.append(
                    {
                        "anchorPath": relative_path,
                        "reason": "outsideAllowedSourceRoots",
                    }
                )
            if not resolved.exists():
                case_violations.append(
                    {
                        "anchorPath": relative_path,
                        "reason": "missingSourceAnchor",
                    }
                )

        if case_violations:
            violating_case_ids.append(case["caseId"])
            violations.append(
                {
                    "caseId": case["caseId"],
                    "violations": case_violations,
                }
            )

    return {
        "value": len(violating_case_ids),
        "violatingCaseIds": sorted(violating_case_ids),
        "violations": sorted(violations, key=lambda item: item["caseId"]),
        "allowedSourceRoots": normalized_roots,
        "reason": "Offline corpus hygiene proxy for capture-policy compliance.",
    }


def build_metrics(
    reports: list[dict[str, Any]],
    catalog: dict[str, Any],
    config: dict[str, Any],
) -> dict[str, Any]:
    assist_reports = [report for report in reports if report["module"] == "assist"]
    repair_path_reports = [report for report in reports if report["preferenceCategory"] == "repair"]
    review_reports = [report for report in reports if report["module"] == "review"]
    risk_reports = [report for report in reports if report["preferenceCategory"] == "risk"]
    failed_reports = [report for report in reports if not report.get("passed")]
    unsafe_reports = [report for report in risk_reports if not is_safety_intact(report)]
    quick_feedback_actions = set(config.get("quickFeedbackActions", []))

    return {
        "preferenceMatchRate": build_rate_metric(
            reports,
            predicate=lambda report: bool(report.get("passed")),
            reason="All selected benchmark cases that still match the frozen teacher-preference baseline.",
        ),
        "assistAcceptanceRate": build_rate_metric(
            assist_reports,
            predicate=lambda report: bool(report.get("passed")),
            reason="Benchmark proxy: assist suggestions that would be accepted because they match the frozen teacher-preferred outcome.",
        ),
        "repairPathHitRate": build_rate_metric(
            repair_path_reports,
            predicate=lambda report: bool(report.get("passed")),
            reason="Benchmark cases in the repair category whose repair or re-teach path still matches the frozen preference baseline.",
        ),
        "teacherOverrideRate": {
            "value": rounded_rate(len(failed_reports), len(reports)),
            "numerator": len(failed_reports),
            "denominator": len(reports),
            "overrideCaseIds": sorted_case_ids(failed_reports),
            "reason": "Benchmark proxy: cases that would still require a teacher override because actual output diverged from the frozen preferred result.",
        },
        "unsafeAutoExecutionRegression": {
            "value": len(unsafe_reports),
            "regressionCaseIds": sorted_case_ids(unsafe_reports),
            "reason": "Risk-category cases whose core safety decision no longer matches the frozen safe outcome.",
        },
        "quickFeedbackCompletionRate": build_rate_metric(
            review_reports,
            predicate=lambda report: is_quick_feedback_completed(report, quick_feedback_actions),
            reason="Review cases that generated a teacher-usable quick-feedback action and stayed aligned with the frozen preferred result.",
        ),
        "medianFeedbackLatencySeconds": build_latency_metric(review_reports),
        "capturePolicyViolationCount": build_capture_policy_metric(
            catalog,
            allowed_source_roots=config.get("allowedSourceRoots", []),
        ),
    }


def metric_value(metrics: dict[str, Any], name: str) -> float | int | None:
    payload = metrics.get(name) or {}
    return payload.get("value")


def evaluate_gates(metrics: dict[str, Any], config: dict[str, Any]) -> dict[str, Any]:
    gate_results = []
    baseline = config.get("baseline", {})

    for metric_name, gate in (config.get("gates") or {}).items():
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
            result["reason"] = "Metric is unavailable for the selected case subset."
            gate_results.append(result)
            continue

        if gate_type == "minimum":
            threshold = gate.get("value")
            result["threshold"] = threshold
            result["passed"] = actual >= threshold
            result["operator"] = ">="
        elif gate_type == "maximum":
            threshold = gate.get("value")
            result["threshold"] = threshold
            result["passed"] = actual <= threshold
            result["operator"] = "<="
        elif gate_type == "baselineDeltaMaximum":
            baseline_metric = gate.get("baselineMetric", metric_name)
            baseline_value = baseline.get(baseline_metric)
            if baseline_value is None:
                raise BenchmarkMetricsError(
                    f"Baseline metric {baseline_metric!r} is missing from config."
                )
            delta = gate.get("delta", 0)
            allowed_max = baseline_value + delta
            result["baselineMetric"] = baseline_metric
            result["baselineValue"] = baseline_value
            result["allowedDelta"] = delta
            result["threshold"] = round(allowed_max, 4)
            result["passed"] = actual <= allowed_max
            result["operator"] = "<="
        else:
            raise BenchmarkMetricsError(f"Unsupported gate type for {metric_name}: {gate_type}")

        gate_results.append(result)

    failed = [item for item in gate_results if item.get("passed") is False]
    skipped = [item for item in gate_results if item.get("skipped")]
    return {
        "gateConfigId": config.get("configId"),
        "passed": len(failed) == 0,
        "total": len(gate_results),
        "failed": len(failed),
        "skipped": len(skipped),
        "results": gate_results,
    }


def build_summary(
    manifest: dict[str, Any],
    catalog: dict[str, Any],
    config: dict[str, Any],
    *,
    manifest_path: Path,
    catalog_path: Path,
    config_path: Path,
    output_path: Path,
    benchmark_root: Path,
) -> dict[str, Any]:
    reports = normalize_reports(manifest, benchmark_root)
    metrics = build_metrics(reports, catalog, config)
    gates = evaluate_gates(metrics, config)
    return {
        "schemaVersion": SUMMARY_SCHEMA_VERSION,
        "generatedAt": now_iso(),
        "benchmarkId": manifest.get("benchmarkId"),
        "manifestPath": repo_relative(manifest_path),
        "catalogPath": repo_relative(catalog_path),
        "configPath": repo_relative(config_path),
        "outputPath": repo_relative(output_path),
        "selectedCaseCount": len(reports),
        "selectedCaseIds": sorted_case_ids(reports),
        "metrics": metrics,
        "gates": gates,
        "notes": [
            "All metrics in this summary are offline benchmark proxies, not live production telemetry.",
            "teacherOverrideRate is derived from benchmark divergences that would still require teacher correction.",
            "capturePolicyViolationCount only audits benchmark source anchors against approved corpus roots.",
        ],
    }


def print_summary(summary: dict[str, Any]) -> None:
    gates = summary["gates"]
    metrics = summary["metrics"]
    print(
        "Preference metrics summary finished. "
        f"gates={'PASS' if gates['passed'] else 'FAIL'} "
        f"failed={gates['failed']} skipped={gates['skipped']} "
        f"output={summary['outputPath']}"
    )
    ordered_metrics = [
        "preferenceMatchRate",
        "assistAcceptanceRate",
        "repairPathHitRate",
        "teacherOverrideRate",
        "unsafeAutoExecutionRegression",
        "quickFeedbackCompletionRate",
        "medianFeedbackLatencySeconds",
        "capturePolicyViolationCount",
    ]
    for name in ordered_metrics:
        value = metrics[name]["value"]
        print(f"{name}={value}")


def main() -> int:
    args = parse_args()
    benchmark_root = args.benchmark_root.resolve()
    manifest_path = args.manifest.resolve()
    config_path = args.config.resolve()
    manifest = read_json(manifest_path)
    catalog_path = resolve_catalog_path(manifest, benchmark_root, args.catalog)
    catalog = read_json(catalog_path)
    config = read_json(config_path)
    output_path = args.output.resolve() if args.output else benchmark_root / "metrics-summary.json"

    summary = build_summary(
        manifest,
        catalog,
        config,
        manifest_path=manifest_path,
        catalog_path=catalog_path,
        config_path=config_path,
        output_path=output_path.resolve(),
        benchmark_root=benchmark_root,
    )
    write_json(output_path, summary)
    print_summary(summary)

    if args.check_gates and not summary["gates"]["passed"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
