#!/usr/bin/env python3
"""Run the semantic-action end-to-end benchmark corpus."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
PACKAGE_PATH = REPO_ROOT / "apps/macos"
DEFAULT_BENCHMARK_ROOT = REPO_ROOT / "data/benchmarks/semantic-action-e2e"
DEFAULT_CATALOG_PATH = DEFAULT_BENCHMARK_ROOT / "catalog.json"
REPLAY_VERIFY_TARGET = "OpenStaffReplayVerifyCLI"
XCODE_DEVELOPER_DIR = Path("/Applications/Xcode.app/Contents/Developer")
MANIFEST_SCHEMA_VERSION = "openstaff.semantic-action-e2e-benchmark.manifest.v0"
CASE_REPORT_SCHEMA_VERSION = "openstaff.semantic-action-e2e-benchmark.case-report.v0"
SOURCE_RECORD_SCHEMA_VERSION = "openstaff.semantic-action-e2e-benchmark.source-record.v0"
ATTEMPT_SCHEMA_VERSION = "openstaff.semantic-action-e2e-benchmark.attempt.v0"

sys.path.insert(0, str(REPO_ROOT / "scripts/learning"))

from semantic_action_store import (  # noqa: E402
    SemanticActionAssertionRecord,
    SemanticActionMigrationManager,
    SemanticActionRecord,
    SemanticActionRepository,
    SemanticActionTargetRecord,
)


class BenchmarkError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the OpenStaff semantic-action end-to-end benchmark."
    )
    parser.add_argument(
        "--catalog",
        type=Path,
        default=DEFAULT_CATALOG_PATH,
        help=f"Benchmark catalog JSON path (default: {DEFAULT_CATALOG_PATH}).",
    )
    parser.add_argument(
        "--benchmark-root",
        type=Path,
        default=DEFAULT_BENCHMARK_ROOT,
        help=f"Output root for generated benchmark artifacts (default: {DEFAULT_BENCHMARK_ROOT}).",
    )
    parser.add_argument(
        "--case-id",
        action="append",
        default=[],
        help="Run only the selected case ID. May be specified multiple times.",
    )
    parser.add_argument(
        "--case-limit",
        type=int,
        help="Limit the number of selected benchmark cases.",
    )
    parser.add_argument(
        "--replay-verify-executable",
        type=str,
        help="Optional prebuilt OpenStaffReplayVerifyCLI executable path.",
    )
    parser.add_argument(
        "--environment",
        type=str,
        default="benchmark",
        help="Environment label injected into benchmark execution logs (default: benchmark).",
    )
    parser.add_argument(
        "--max-retries",
        type=int,
        default=1,
        help="Maximum retry attempts per failed case (default: 1).",
    )
    parser.add_argument(
        "--repeat-count",
        type=int,
        default=1,
        help="Repeat the selected case set sequentially to simulate longer sessions (default: 1).",
    )
    parser.add_argument(
        "--report",
        type=Path,
        help="Optional explicit manifest/report path. Default: <benchmark-root>/manifest.json",
    )
    return parser.parse_args()


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def build_swift_env() -> dict[str, str]:
    env = os.environ.copy()
    env["HOME"] = "/tmp"

    if XCODE_DEVELOPER_DIR.exists():
        env["DEVELOPER_DIR"] = str(XCODE_DEVELOPER_DIR)

    cache_key = hashlib.sha256(str(REPO_ROOT).encode("utf-8")).hexdigest()[:12]
    module_cache = REPO_ROOT / f".build/module-cache-{cache_key}"
    clang_module_cache = REPO_ROOT / f".build/clang-module-cache-{cache_key}"
    module_cache.mkdir(parents=True, exist_ok=True)
    clang_module_cache.mkdir(parents=True, exist_ok=True)
    env["SWIFTPM_MODULECACHE_OVERRIDE"] = str(module_cache)
    env["CLANG_MODULE_CACHE_PATH"] = str(clang_module_cache)
    return env


def run_command(
    command: list[str],
    *,
    env: dict[str, str] | None = None,
    cwd: Path = REPO_ROOT,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def require_success(completed: subprocess.CompletedProcess[str], context: str) -> None:
    if completed.returncode == 0:
        return

    details = [f"{context} failed with exit code {completed.returncode}."]
    if completed.stdout.strip():
        details.append(f"stdout:\n{completed.stdout.strip()}")
    if completed.stderr.strip():
        details.append(f"stderr:\n{completed.stderr.strip()}")
    raise BenchmarkError("\n".join(details))


def extract_last_json_object(text: str) -> Any:
    stripped = text.strip()
    if not stripped:
        raise BenchmarkError("Command did not emit JSON output.")

    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        end = stripped.rfind("}")
        if end == -1:
            raise BenchmarkError(f"No JSON object found in output: {stripped}") from None

        for start in range(end, -1, -1):
            if stripped[start] != "{":
                continue
            candidate = stripped[start : end + 1]
            try:
                return json.loads(candidate)
            except json.JSONDecodeError:
                continue
        raise BenchmarkError(f"No JSON object found in output: {stripped}") from None


def repo_relative(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(resolved)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 64)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def resolve_catalog_path(path: Path) -> Path:
    resolved = path.resolve()
    if not resolved.exists():
        raise BenchmarkError(f"Benchmark catalog does not exist: {resolved}")
    return resolved


def load_catalog(path: Path) -> dict[str, Any]:
    payload = read_json(path)
    if not isinstance(payload, dict):
        raise BenchmarkError(f"Catalog must be a JSON object: {path}")

    cases = payload.get("cases")
    if not isinstance(cases, list) or not cases:
        raise BenchmarkError(f"Catalog must include a non-empty cases array: {path}")

    case_ids: set[str] = set()
    for index, case in enumerate(cases):
        if not isinstance(case, dict):
            raise BenchmarkError(f"Catalog case[{index}] must be an object.")
        case_id = str(case.get("caseId", "")).strip()
        title = str(case.get("title", "")).strip()
        category = str(case.get("category", "")).strip()
        if not case_id or not title or not category:
            raise BenchmarkError(f"Catalog case[{index}] must define caseId/title/category.")
        if case_id in case_ids:
            raise BenchmarkError(f"Duplicate caseId in catalog: {case_id}")
        case_ids.add(case_id)
        if not isinstance(case.get("coverage"), list) or not case["coverage"]:
            raise BenchmarkError(f"Catalog case[{index}] must define a non-empty coverage list.")
        if not isinstance(case.get("action"), dict):
            raise BenchmarkError(f"Catalog case[{index}] must define an action object.")
        if not isinstance(case.get("expected"), dict):
            raise BenchmarkError(f"Catalog case[{index}] must define an expected object.")
        snapshot_path = case.get("snapshotPath")
        if not isinstance(snapshot_path, str) or not snapshot_path.strip():
            raise BenchmarkError(f"Catalog case[{index}] must define snapshotPath.")
    return payload


def select_cases(
    catalog: dict[str, Any],
    case_ids: list[str],
    case_limit: int | None,
) -> list[dict[str, Any]]:
    selected = list(catalog["cases"])
    if case_ids:
        allowed = set(case_ids)
        selected = [case for case in selected if case["caseId"] in allowed]

    if case_limit is not None:
        selected = selected[: max(case_limit, 0)]

    if not selected:
        raise BenchmarkError("No benchmark cases selected.")
    return selected


def repeat_label(run_index: int, repeat_count: int) -> str | None:
    if repeat_count <= 1:
        return None
    return f"run-{run_index:03d}"


def case_run_id(case: dict[str, Any], run_index: int, repeat_count: int) -> str:
    label = repeat_label(run_index, repeat_count)
    if label is None:
        return str(case["caseId"])
    return f"{case['caseId']}::{label}"


def with_run_suffix(base: str, run_index: int, repeat_count: int) -> str:
    label = repeat_label(run_index, repeat_count)
    if label is None:
        return base
    return f"{base}-{label}"


def resolve_replay_verify_executable(explicit_path: str | None) -> str:
    if explicit_path:
        candidate = Path(explicit_path)
        if not candidate.exists():
            raise BenchmarkError(f"Replay verify executable does not exist: {candidate}")
        return str(candidate.resolve())

    env = build_swift_env()
    build_command = [
        "swift",
        "build",
        "--package-path",
        repo_relative(PACKAGE_PATH),
        "--product",
        REPLAY_VERIFY_TARGET,
    ]
    require_success(run_command(build_command, env=env), "swift build OpenStaffReplayVerifyCLI")

    show_bin_command = [
        "swift",
        "build",
        "--package-path",
        repo_relative(PACKAGE_PATH),
        "--show-bin-path",
    ]
    show_bin_result = run_command(show_bin_command, env=env)
    require_success(show_bin_result, "swift build --show-bin-path")
    executable = Path(show_bin_result.stdout.strip()) / REPLAY_VERIFY_TARGET
    if not executable.exists():
        raise BenchmarkError(f"Replay verify executable not found after build: {executable}")
    return str(executable.resolve())


def resolve_case_snapshot(case: dict[str, Any]) -> Path:
    snapshot_path = (REPO_ROOT / str(case["snapshotPath"])).resolve()
    if not snapshot_path.exists():
        raise BenchmarkError(f"Benchmark snapshot does not exist: {snapshot_path}")
    return snapshot_path


def build_source_record(
    case: dict[str, Any],
    snapshot_path: Path,
    *,
    run_index: int,
    repeat_count: int,
) -> dict[str, Any]:
    action_payload = case["action"]
    fingerprint = hashlib.sha256(
        json.dumps(action_payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
    ).hexdigest()
    return {
        "schemaVersion": SOURCE_RECORD_SCHEMA_VERSION,
        "caseId": case_run_id(case, run_index, repeat_count),
        "sourceCaseId": case["caseId"],
        "runIndex": run_index,
        "repeatCount": repeat_count,
        "category": case["category"],
        "title": case["title"],
        "coverage": case["coverage"],
        "snapshot": {
            "path": repo_relative(snapshot_path),
            "sha256": sha256_file(snapshot_path),
        },
        "actionFingerprint": fingerprint,
        "expected": case["expected"],
    }


def build_action_record(
    case: dict[str, Any],
    *,
    run_index: int,
    repeat_count: int,
) -> SemanticActionRecord:
    action = case["action"]
    action_id = str(action.get("actionId", "")).strip() or case_run_id(case, run_index, repeat_count)
    session_id = with_run_suffix(
        str(action.get("sessionId", "")).strip() or f"benchmark-session-{case['caseId']}",
        run_index,
        repeat_count,
    )
    task_id = with_run_suffix(
        str(action.get("taskId", "")).strip() or f"benchmark-task-{case['caseId']}",
        run_index,
        repeat_count,
    )
    trace_id = with_run_suffix(
        str(action.get("traceId", "")).strip() or f"benchmark-trace-{case['caseId']}",
        run_index,
        repeat_count,
    )
    step_id = with_run_suffix(
        str(action.get("stepId", "")).strip() or f"benchmark-step-{case['caseId']}",
        run_index,
        repeat_count,
    )
    created_at = str(action.get("createdAt", "")).strip() or "2026-03-28T20:00:00Z"
    updated_at = str(action.get("updatedAt", "")).strip() or created_at
    confidence = float(action.get("confidence", 0.95))
    return SemanticActionRecord(
        action_id=action_id,
        session_id=session_id,
        task_id=task_id,
        trace_id=trace_id,
        step_id=step_id,
        action_type=str(action.get("actionType", "")).strip(),
        selector=action.get("selector", {}) if isinstance(action.get("selector"), dict) else {},
        args=action.get("args", {}) if isinstance(action.get("args"), dict) else {},
        context=action.get("context", {}) if isinstance(action.get("context"), dict) else {},
        confidence=confidence,
        created_at=created_at,
        updated_at=updated_at,
        preferred_locator_type=(
            str(action.get("preferredLocatorType", "")).strip() or None
        ),
        manual_review_required=bool(action.get("manualReviewRequired", False)),
    )


def build_target_records(case: dict[str, Any], action_id: str) -> list[SemanticActionTargetRecord]:
    records: list[SemanticActionTargetRecord] = []
    for index, target in enumerate(case["action"].get("targets", []), start=1):
        if not isinstance(target, dict):
            raise BenchmarkError(f"Case {case['caseId']} has a non-object target entry.")
        records.append(
            SemanticActionTargetRecord(
                target_id=str(target.get("targetId", "")).strip()
                or f"{action_id}:target:{index:02d}",
                target_role=str(target.get("targetRole", "")).strip() or "primary",
                ordinal=int(target.get("ordinal", index)),
                locator_type=str(target.get("locatorType", "")).strip() or None,
                selector=target.get("selector", {}) if isinstance(target.get("selector"), dict) else {},
                context=target.get("context", {}) if isinstance(target.get("context"), dict) else {},
                confidence=float(target.get("confidence")) if target.get("confidence") is not None else None,
                is_preferred=bool(target.get("isPreferred", index == 1)),
                created_at=str(target.get("createdAt", "")).strip() or "2026-03-28T20:00:00Z",
            )
        )
    return records


def build_assertion_records(
    case: dict[str, Any],
    action_id: str,
) -> list[SemanticActionAssertionRecord]:
    records: list[SemanticActionAssertionRecord] = []
    for index, assertion in enumerate(case["action"].get("assertions", []), start=1):
        if not isinstance(assertion, dict):
            raise BenchmarkError(f"Case {case['caseId']} has a non-object assertion entry.")
        records.append(
            SemanticActionAssertionRecord(
                assertion_id=str(assertion.get("assertionId", "")).strip()
                or f"{action_id}:assertion:{index:02d}",
                assertion_type=str(assertion.get("assertionType", "")).strip()
                or str(assertion.get("type", "")).strip(),
                assertion=assertion.get("payload", assertion.get("assertion", {}))
                if isinstance(assertion.get("payload", assertion.get("assertion", {})), dict)
                else {},
                created_at=str(assertion.get("createdAt", "")).strip() or "2026-03-28T20:00:00Z",
                source=str(assertion.get("source", "")).strip() or "benchmark",
                is_required=bool(assertion.get("isRequired", True)),
                ordinal=int(assertion.get("ordinal", index)),
            )
        )
    return records


def materialize_case_database(
    case: dict[str, Any],
    db_path: Path,
    *,
    run_index: int,
    repeat_count: int,
) -> str:
    manager = SemanticActionMigrationManager(db_path)
    manager.migrate_up()
    repository = SemanticActionRepository(db_path)
    action_record = build_action_record(case, run_index=run_index, repeat_count=repeat_count)
    repository.replace_action(
        action_record,
        targets=build_target_records(case, action_record.action_id),
        assertions=build_assertion_records(case, action_record.action_id),
    )
    return action_record.action_id


def compare_expected(
    expected: Any,
    actual: Any,
    *,
    path: str,
    mismatches: list[str],
) -> None:
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            mismatches.append(f"{path}: expected object, got {type(actual).__name__}.")
            return
        for key, value in expected.items():
            if key not in actual:
                mismatches.append(f"{path}.{key}: missing from actual payload.")
                continue
            compare_expected(value, actual[key], path=f"{path}.{key}", mismatches=mismatches)
        return

    if isinstance(expected, list):
        if expected != actual:
            mismatches.append(f"{path}: expected {expected!r}, got {actual!r}.")
        return

    if expected != actual:
        mismatches.append(f"{path}: expected {expected!r}, got {actual!r}.")


def run_attempt(
    case: dict[str, Any],
    *,
    run_index: int,
    repeat_count: int,
    attempt_number: int,
    case_output_dir: Path,
    replay_verify_executable: str,
    environment: str,
) -> dict[str, Any]:
    attempt_dir = case_output_dir / "attempts" / f"attempt-{attempt_number:02d}"
    attempt_dir.mkdir(parents=True, exist_ok=True)

    snapshot_path = resolve_case_snapshot(case)
    db_path = attempt_dir / "semantic-actions.sqlite"
    action_id = materialize_case_database(
        case,
        db_path,
        run_index=run_index,
        repeat_count=repeat_count,
    )

    command = [
        replay_verify_executable,
        "--semantic-action-db",
        str(db_path),
        "--action-id",
        action_id,
        "--snapshot",
        str(snapshot_path),
        "--environment",
        environment,
        "--json",
    ]
    if bool(case.get("dryRun", True)):
        command.append("--dry-run")
    if bool(case.get("teacherConfirmed", False)):
        command.append("--teacher-confirmed")

    completed = run_command(command, env=build_swift_env())
    stdout_path = attempt_dir / "cli.stdout.txt"
    stderr_path = attempt_dir / "cli.stderr.txt"
    write_text(stdout_path, completed.stdout)
    write_text(stderr_path, completed.stderr)

    report_payload = extract_last_json_object(completed.stdout)
    if not isinstance(report_payload, dict):
        raise BenchmarkError(f"Replay verify report for {case['caseId']} is not a JSON object.")
    cli_report_path = attempt_dir / "cli-report.json"
    write_json(cli_report_path, report_payload)

    repository = SemanticActionRepository(db_path)
    action_payload = repository.get_action(action_id)
    if action_payload is None:
        raise BenchmarkError(f"Benchmark action disappeared from SQLite store: {action_id}")
    execution_logs = action_payload.get("execution_logs", [])
    if not execution_logs:
        raise BenchmarkError(f"Replay verify did not append execution logs for case {case['caseId']}.")
    execution_log = execution_logs[-1]
    execution_log_path = attempt_dir / "execution-log.json"
    write_json(execution_log_path, execution_log)

    expected = case["expected"]
    actual_projection = {
        "exitCode": completed.returncode,
        "report": report_payload,
        "executionLog": {
            "status": execution_log.get("status"),
            "errorCode": execution_log.get("error_code"),
            "environment": execution_log.get("result_json", {}).get("environment"),
        },
    }
    mismatches: list[str] = []
    compare_expected(expected, actual_projection, path="expected", mismatches=mismatches)
    passed = len(mismatches) == 0

    attempt_payload = {
        "schemaVersion": ATTEMPT_SCHEMA_VERSION,
        "attemptNumber": attempt_number,
        "caseId": case_run_id(case, run_index, repeat_count),
        "sourceCaseId": case["caseId"],
        "runIndex": run_index,
        "passed": passed,
        "mismatches": mismatches,
        "artifacts": {
            "semanticActionDatabasePath": repo_relative(db_path),
            "snapshotPath": repo_relative(snapshot_path),
            "stdoutPath": repo_relative(stdout_path),
            "stderrPath": repo_relative(stderr_path),
            "cliReportPath": repo_relative(cli_report_path),
            "executionLogPath": repo_relative(execution_log_path),
        },
        "results": actual_projection,
    }
    attempt_report_path = attempt_dir / "attempt-report.json"
    write_json(attempt_report_path, attempt_payload)
    attempt_payload["artifacts"]["attemptReportPath"] = repo_relative(attempt_report_path)
    write_json(attempt_report_path, attempt_payload)
    return attempt_payload


def process_case(
    case: dict[str, Any],
    benchmark_root: Path,
    *,
    run_index: int,
    repeat_count: int,
    replay_verify_executable: str,
    environment: str,
    max_retries: int,
) -> dict[str, Any]:
    case_output_dir = benchmark_root / "generated" / case["caseId"]
    if repeat_count > 1:
        case_output_dir = case_output_dir / "runs" / repeat_label(run_index, repeat_count)
    case_output_dir.mkdir(parents=True, exist_ok=True)

    snapshot_path = resolve_case_snapshot(case)
    source_record = build_source_record(
        case,
        snapshot_path,
        run_index=run_index,
        repeat_count=repeat_count,
    )
    source_record_path = case_output_dir / "source-record.json"
    write_json(source_record_path, source_record)

    attempts: list[dict[str, Any]] = []
    final_attempt: dict[str, Any] | None = None
    total_attempts = max(1, max_retries + 1)
    for attempt_number in range(1, total_attempts + 1):
        attempt_payload = run_attempt(
            case,
            run_index=run_index,
            repeat_count=repeat_count,
            attempt_number=attempt_number,
            case_output_dir=case_output_dir,
            replay_verify_executable=replay_verify_executable,
            environment=environment,
        )
        attempts.append(attempt_payload)
        final_attempt = attempt_payload
        if attempt_payload["passed"]:
            break

    assert final_attempt is not None
    flaky_recovered = final_attempt["passed"] and len(attempts) > 1

    case_report = {
        "schemaVersion": CASE_REPORT_SCHEMA_VERSION,
        "caseId": case_run_id(case, run_index, repeat_count),
        "sourceCaseId": case["caseId"],
        "runIndex": run_index,
        "title": case["title"],
        "category": case["category"],
        "coverage": case["coverage"],
        "passed": final_attempt["passed"],
        "attemptCount": len(attempts),
        "flakeRecovered": flaky_recovered,
        "summary": (
            f"status={final_attempt['results']['report'].get('status')} "
            f"exitCode={final_attempt['results']['exitCode']} "
            f"attempts={len(attempts)}"
        ),
        "artifacts": {
            "sourceRecordPath": repo_relative(source_record_path),
            "finalAttemptReportPath": final_attempt["artifacts"]["attemptReportPath"],
        },
        "expected": case["expected"],
        "results": final_attempt["results"],
        "attempts": [
            {
                "attemptNumber": attempt["attemptNumber"],
                "passed": attempt["passed"],
                "attemptReportPath": attempt["artifacts"]["attemptReportPath"],
            }
            for attempt in attempts
        ],
    }
    case_report_path = case_output_dir / "case-report.json"
    write_json(case_report_path, case_report)
    case_report["artifacts"]["caseReportPath"] = repo_relative(case_report_path)
    write_json(case_report_path, case_report)
    return case_report


def build_manifest(
    *,
    benchmark_root: Path,
    catalog_path: Path,
    benchmark_id: str,
    case_reports: list[dict[str, Any]],
    max_retries: int,
    repeat_count: int,
    environment: str,
) -> dict[str, Any]:
    failed_cases = [case["caseId"] for case in case_reports if not case["passed"]]
    category_counts = Counter(case["category"] for case in case_reports)
    coverage_counts = Counter(
        coverage
        for case in case_reports
        for coverage in case.get("coverage", [])
    )
    flaky_recovered_cases = [
        case["caseId"] for case in case_reports if case.get("flakeRecovered")
    ]
    return {
        "schemaVersion": MANIFEST_SCHEMA_VERSION,
        "benchmarkId": benchmark_id,
        "generatedAt": now_iso(),
        "benchmarkRoot": repo_relative(benchmark_root),
        "catalogPath": repo_relative(catalog_path),
        "environment": environment,
        "maxRetries": max_retries,
        "repeatCount": repeat_count,
        "sourceCaseCount": len({case["sourceCaseId"] for case in case_reports}),
        "totalCases": len(case_reports),
        "passedCases": len(case_reports) - len(failed_cases),
        "failedCases": failed_cases,
        "categoryCounts": dict(sorted(category_counts.items())),
        "coverageCounts": dict(sorted(coverage_counts.items())),
        "flakyRecoveredCases": flaky_recovered_cases,
        "cases": case_reports,
    }


def main() -> int:
    args = parse_args()
    benchmark_root = args.benchmark_root.resolve()
    benchmark_root.mkdir(parents=True, exist_ok=True)

    catalog_path = resolve_catalog_path(args.catalog)
    catalog = load_catalog(catalog_path)
    selected_cases = select_cases(catalog, args.case_id, args.case_limit)
    replay_verify_executable = resolve_replay_verify_executable(args.replay_verify_executable)

    case_reports: list[dict[str, Any]] = []
    repeat_count = max(args.repeat_count, 1)
    for run_index in range(1, repeat_count + 1):
        for case in selected_cases:
            print(
                f"[semantic-benchmark] case={case_run_id(case, run_index, repeat_count)} "
                f"category={case['category']}"
            )
            case_reports.append(
                process_case(
                    case,
                    benchmark_root,
                    run_index=run_index,
                    repeat_count=repeat_count,
                    replay_verify_executable=replay_verify_executable,
                    environment=args.environment.strip().lower(),
                    max_retries=max(args.max_retries, 0),
                )
            )

    benchmark_id = (
        str(catalog.get("benchmarkId", "semantic-action-e2e-benchmark")).strip()
        or "semantic-action-e2e-benchmark"
    )
    manifest = build_manifest(
        benchmark_root=benchmark_root,
        catalog_path=catalog_path,
        benchmark_id=benchmark_id,
        case_reports=case_reports,
        max_retries=max(args.max_retries, 0),
        repeat_count=repeat_count,
        environment=args.environment.strip().lower(),
    )
    report_path = args.report.resolve() if args.report else benchmark_root / "manifest.json"
    write_json(report_path, manifest)

    print(
        f"[semantic-benchmark] total={manifest['totalCases']} "
        f"passed={manifest['passedCases']} failed={len(manifest['failedCases'])} "
        f"flakes={len(manifest['flakyRecoveredCases'])}"
    )
    print(f"[semantic-benchmark] manifest={repo_relative(report_path)}")
    return 0 if not manifest["failedCases"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
