#!/usr/bin/env python3
"""Aggregate semantic-action e2e benchmark metrics and evaluate gates."""

from __future__ import annotations

import argparse
import json
import math
from datetime import datetime
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BENCHMARK_ROOT = REPO_ROOT / "data/benchmarks/semantic-action-e2e"
DEFAULT_MANIFEST_PATH = DEFAULT_BENCHMARK_ROOT / "manifest.json"
DEFAULT_CONFIG_PATH = DEFAULT_BENCHMARK_ROOT / "metrics-v0.json"
SUMMARY_SCHEMA_VERSION = "openstaff.semantic-action-e2e-metrics-summary.v0"


class BenchmarkMetricsError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Aggregate SEM-402 semantic-action e2e metrics from benchmark artifacts."
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
        "--config",
        type=Path,
        default=DEFAULT_CONFIG_PATH,
        help=f"Metric config JSON path (default: {DEFAULT_CONFIG_PATH}).",
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


def rounded_rate(numerator: int, denominator: int) -> float | None:
    if denominator == 0:
        return None
    return round(numerator / denominator, 4)


def percentile(values: list[float], ratio: float) -> float | None:
    if not values:
        return None
    if len(values) == 1:
        return round(values[0], 4)

    ordered = sorted(values)
    index = math.ceil((len(ordered) - 1) * ratio)
    index = max(0, min(index, len(ordered) - 1))
    return round(ordered[index], 4)


def case_ids(reports: list[dict[str, Any]]) -> list[str]:
    return sorted(str(report["caseId"]) for report in reports)


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
        "matchedCaseIds": case_ids(matched),
        "missedCaseIds": case_ids([report for report in reports if not predicate(report)]),
        "reason": reason,
    }


def matched_locator_type(report: dict[str, Any]) -> str | None:
    return (
        (((report.get("results") or {}).get("report") or {}).get("matchedLocatorType"))
        or None
    )


def selector_hit_path(report: dict[str, Any]) -> list[str]:
    value = (((report.get("results") or {}).get("report") or {}).get("selectorHitPath"))
    if isinstance(value, list):
        return [str(item) for item in value]
    return []


def error_code(report: dict[str, Any]) -> str | None:
    value = (((report.get("results") or {}).get("report") or {}).get("errorCode"))
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def duration_ms(report: dict[str, Any]) -> float | None:
    value = (((report.get("results") or {}).get("report") or {}).get("durationMs"))
    if value is None:
        return None
    try:
        return round(float(value), 4)
    except (TypeError, ValueError):
        raise BenchmarkMetricsError(
            f"Invalid durationMs in case {report.get('caseId')}: {value!r}"
        ) from None


def build_duration_metric(reports: list[dict[str, Any]], *, quantile: float, reason: str) -> dict[str, Any]:
    samples = []
    missing_case_ids = []
    for report in reports:
        value = duration_ms(report)
        if value is None:
            missing_case_ids.append(str(report["caseId"]))
            continue
        samples.append({"caseId": str(report["caseId"]), "durationMs": value})

    values = [sample["durationMs"] for sample in samples]
    return {
        "value": percentile(values, quantile),
        "sampleCount": len(samples),
        "samples": samples,
        "missingCaseIds": sorted(missing_case_ids),
        "reason": reason,
    }


def build_max_duration_metric(reports: list[dict[str, Any]]) -> dict[str, Any]:
    samples = []
    for report in reports:
        value = duration_ms(report)
        if value is not None:
            samples.append({"caseId": str(report["caseId"]), "durationMs": value})

    if not samples:
        return {
            "value": None,
            "sampleCount": 0,
            "samples": [],
            "reason": "No duration samples were available in the selected benchmark run.",
        }

    winner = max(samples, key=lambda sample: sample["durationMs"])
    return {
        "value": winner["durationMs"],
        "sampleCount": len(samples),
        "caseId": winner["caseId"],
        "samples": samples,
        "reason": "Maximum observed semantic action duration across the selected benchmark runs.",
    }


def build_timeout_metric(reports: list[dict[str, Any]]) -> dict[str, Any]:
    timeout_reports = [
        report for report in reports
        if (error_code(report) or "").upper().endswith("TIMEOUT")
        or "TIMEOUT" in (error_code(report) or "").upper()
    ]
    return {
        "value": len(timeout_reports),
        "timeoutCaseIds": case_ids(timeout_reports),
        "reason": "Cases that terminated with a structured timeout error code.",
    }


def build_stability_metric(manifest: dict[str, Any], reports: list[dict[str, Any]]) -> dict[str, Any]:
    repeat_count = int(manifest.get("repeatCount") or 1)
    if repeat_count <= 1:
        return {
            "value": None,
            "repeatCount": repeat_count,
            "reason": "Stability pressure metric is only available when repeatCount > 1.",
        }

    passed = [report for report in reports if bool(report.get("passed"))]
    return {
        "value": rounded_rate(len(passed), len(reports)),
        "repeatCount": repeat_count,
        "numerator": len(passed),
        "denominator": len(reports),
        "failedCaseIds": case_ids([report for report in reports if not report.get("passed")]),
        "reason": "Repeated benchmark runs used as a pressure proxy for longer semantic sessions.",
    }


def build_snapshot_recovery_metric(reports: list[dict[str, Any]]) -> dict[str, Any]:
    reports_with_post_assertions = [
        report for report in reports
        if isinstance(((report.get("results") or {}).get("report") or {}).get("postAssertions"), dict)
    ]
    if not reports_with_post_assertions:
        return {
            "value": None,
            "sampleCount": 0,
            "reason": "No post-assertion reports were emitted in the selected benchmark run.",
        }

    recovered = [
        report for report in reports_with_post_assertions
        if bool((((report.get("results") or {}).get("report") or {}).get("postAssertions") or {}).get("recoveredAfterRetry"))
    ]
    return {
        "value": rounded_rate(len(recovered), len(reports_with_post_assertions)),
        "sampleCount": len(reports_with_post_assertions),
        "recoveredCaseIds": case_ids(recovered),
        "reason": "Post-assertion snapshots that needed one or more retries before stabilizing.",
    }


def build_metrics(manifest: dict[str, Any]) -> dict[str, Any]:
    reports = manifest.get("cases") or []
    if not isinstance(reports, list) or not reports:
        raise BenchmarkMetricsError("Benchmark manifest does not contain any case reports.")

    flaky_recovered_cases = [str(item) for item in manifest.get("flakyRecoveredCases", [])]
    flaky_recovered_lookup = set(flaky_recovered_cases)

    return {
        "casePassRate": build_rate_metric(
            reports,
            predicate=lambda report: bool(report.get("passed")),
            reason="Selected semantic benchmark runs that still match the frozen expected execution result.",
        ),
        "selectorResolutionRate": build_rate_metric(
            reports,
            predicate=lambda report: bool(selector_hit_path(report))
            and matched_locator_type(report) not in (None, "coordinateFallback"),
            reason="Runs that resolved a semantic locator path without degrading to coordinate fallback.",
        ),
        "p50ActionDurationMs": build_duration_metric(
            reports,
            quantile=0.50,
            reason="Median semantic action duration observed across the selected benchmark runs.",
        ),
        "p95ActionDurationMs": build_duration_metric(
            reports,
            quantile=0.95,
            reason="P95 semantic action duration observed across the selected benchmark runs.",
        ),
        "maxActionDurationMs": build_max_duration_metric(reports),
        "timeoutCount": build_timeout_metric(reports),
        "flakeRecoveryRate": {
            "value": rounded_rate(len(flaky_recovered_cases), len(reports)),
            "numerator": len(flaky_recovered_cases),
            "denominator": len(reports),
            "matchedCaseIds": sorted(flaky_recovered_lookup),
            "reason": "Runs that needed one or more retry attempts before converging to a pass.",
        },
        "stabilityPassRate": build_stability_metric(manifest, reports),
        "postActionSnapshotRecoveryRate": build_snapshot_recovery_metric(reports),
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
            result["reason"] = "Metric is unavailable for the selected benchmark run."
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
    config: dict[str, Any],
    *,
    manifest_path: Path,
    config_path: Path,
    output_path: Path,
) -> dict[str, Any]:
    reports = manifest.get("cases") or []
    if not isinstance(reports, list) or not reports:
        raise BenchmarkMetricsError("Benchmark manifest does not contain any case reports.")

    metrics = build_metrics(manifest)
    gates = evaluate_gates(metrics, config)
    return {
        "schemaVersion": SUMMARY_SCHEMA_VERSION,
        "generatedAt": now_iso(),
        "benchmarkId": manifest.get("benchmarkId"),
        "manifestPath": repo_relative(manifest_path),
        "configPath": repo_relative(config_path),
        "outputPath": repo_relative(output_path),
        "selectedCaseCount": len(reports),
        "selectedCaseIds": case_ids(reports),
        "repeatCount": int(manifest.get("repeatCount") or 1),
        "metrics": metrics,
        "gates": gates,
        "notes": [
            "All metrics in this summary are offline semantic benchmark proxies, not live production telemetry.",
            "stabilityPassRate is only evaluated when benchmark repeatCount > 1.",
            "timeoutCount keys off structured TIMEOUT-style error codes emitted by the semantic executor.",
        ],
    }


def print_summary(summary: dict[str, Any]) -> None:
    gates = summary["gates"]
    metrics = summary["metrics"]
    print(
        "Semantic action e2e metrics summary finished. "
        f"gates={'PASS' if gates['passed'] else 'FAIL'} "
        f"failed={gates['failed']} skipped={gates['skipped']} "
        f"output={summary['outputPath']}"
    )
    ordered_metrics = [
        "casePassRate",
        "selectorResolutionRate",
        "p50ActionDurationMs",
        "p95ActionDurationMs",
        "maxActionDurationMs",
        "timeoutCount",
        "flakeRecoveryRate",
        "stabilityPassRate",
        "postActionSnapshotRecoveryRate",
    ]
    for name in ordered_metrics:
        print(f"{name}={metrics[name]['value']}")


def main() -> int:
    args = parse_args()
    benchmark_root = args.benchmark_root.resolve()
    manifest_path = args.manifest.resolve()
    config_path = args.config.resolve()
    output_path = args.output.resolve() if args.output else benchmark_root / "metrics-summary.json"

    manifest = read_json(manifest_path)
    config = read_json(config_path)
    summary = build_summary(
        manifest,
        config,
        manifest_path=manifest_path,
        config_path=config_path,
        output_path=output_path.resolve(),
    )
    write_json(output_path, summary)
    print_summary(summary)

    if args.check_gates and not summary["gates"]["passed"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
