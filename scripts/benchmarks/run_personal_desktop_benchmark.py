#!/usr/bin/env python3
"""
Materialize and run the Personal Desktop Benchmark corpus.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BENCHMARK_ROOT = REPO_ROOT / "data/benchmarks/personal-desktop"
DEFAULT_CATALOG_PATH = DEFAULT_BENCHMARK_ROOT / "catalog.json"
DEFAULT_LLM_OUTPUT_PATH = REPO_ROOT / "scripts/skills/examples/llm-output.sample.terminal-invalid.txt"
MAPPER_PATH = REPO_ROOT / "scripts/skills/openclaw_skill_mapper.py"
PREFLIGHT_PATH = REPO_ROOT / "scripts/validation/validate_skill_bundle.py"
PACKAGE_PATH = REPO_ROOT / "apps/macos"
OPENCLAW_TARGET = "OpenStaffOpenClawCLI"
XCODE_DEVELOPER_DIR = Path("/Applications/Xcode.app/Contents/Developer")
MANIFEST_SCHEMA_VERSION = "openstaff.personal-desktop-benchmark.manifest.v0"
CASE_REPORT_SCHEMA_VERSION = "openstaff.personal-desktop-benchmark.case-report.v0"
SOURCE_RECORD_SCHEMA_VERSION = "openstaff.personal-desktop-benchmark.source-record.v0"
REVIEW_SCHEMA_VERSION = "openstaff.personal-desktop-benchmark.review.v0"
SKILL_NAME_LIMIT = 64


class BenchmarkError(RuntimeError):
    pass


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the OpenStaff Personal Desktop Benchmark.")
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
        "--skip-openclaw",
        action="store_true",
        help="Skip OpenClaw execution and only materialize skill/preflight artifacts.",
    )
    parser.add_argument(
        "--openclaw-executable",
        type=str,
        help="Optional prebuilt OpenStaffOpenClawCLI executable path. When omitted, the runner builds one.",
    )
    parser.add_argument(
        "--report",
        type=Path,
        help="Optional explicit manifest/report path. Default: <benchmark-root>/manifest.json",
    )
    return parser.parse_args()


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


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


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 64)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def repo_relative(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(resolved)


def normalize_path_value(value: str) -> str:
    if not value:
        return value

    candidate = Path(value)
    if candidate.is_absolute():
        try:
            return candidate.resolve().relative_to(REPO_ROOT).as_posix()
        except ValueError:
            return value
    return value


def normalize_path_fields(payload: Any) -> Any:
    if isinstance(payload, dict):
        normalized: dict[str, Any] = {}
        for key, value in payload.items():
            if isinstance(value, str) and (key.endswith("Path") or key.endswith("DirectoryPath")):
                normalized[key] = normalize_path_value(value)
            else:
                normalized[key] = normalize_path_fields(value)
        return normalized
    if isinstance(payload, list):
        return [normalize_path_fields(item) for item in payload]
    return payload


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


def slugify(value: str, fallback: str) -> str:
    normalized = value.strip().lower()
    normalized = re.sub(r"[^a-z0-9_-]+", "-", normalized)
    normalized = re.sub(r"-{2,}", "-", normalized).strip("-")
    if not normalized:
        normalized = fallback
    return normalized[:SKILL_NAME_LIMIT]


def extract_task_timestamp(task_id: str) -> str | None:
    match = re.search(r"(20\d{6}-\d{6})", task_id)
    return match.group(1) if match else None


def validate_jsonl(path: Path) -> int:
    line_count = 0
    with path.open("r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            line = raw_line.strip()
            if not line:
                continue
            try:
                json.loads(line)
            except json.JSONDecodeError as exc:
                raise BenchmarkError(f"Invalid JSONL line in {path} at line {line_number}: {exc}") from exc
            line_count += 1

    if line_count == 0:
        raise BenchmarkError(f"Raw event log is empty: {path}")
    return line_count


def find_unique_case_file(root: Path, task_id: str) -> Path:
    matches = sorted(root.rglob(f"{task_id}.json"))
    if len(matches) != 1:
        raise BenchmarkError(f"Expected exactly one file for taskId={task_id} under {root}, found {len(matches)}.")
    return matches[0]


def resolve_raw_event_log(session_id: str, task_id: str) -> Path:
    candidates = sorted((REPO_ROOT / "data/raw-events").rglob(f"{session_id}*.jsonl"))
    if not candidates:
        raise BenchmarkError(f"No raw event log found for sessionId={session_id}.")

    task_timestamp = extract_task_timestamp(task_id)
    if task_timestamp:
        filtered = [path for path in candidates if task_timestamp in path.name]
        if len(filtered) == 1:
            return filtered[0]
        if len(filtered) > 1:
            raise BenchmarkError(
                f"Multiple raw event logs match taskId={task_id}: {', '.join(repo_relative(path) for path in filtered)}"
            )

    if len(candidates) == 1:
        return candidates[0]

    raise BenchmarkError(
        f"Multiple raw event logs match sessionId={session_id}; unable to disambiguate taskId={task_id}: "
        + ", ".join(repo_relative(path) for path in candidates)
    )


def discover_case_sources(task_id: str) -> dict[str, Any]:
    knowledge_path = find_unique_case_file(REPO_ROOT / "data/knowledge", task_id)
    task_chunk_path = find_unique_case_file(REPO_ROOT / "data/task-chunks", task_id)
    knowledge_item = read_json(knowledge_path)
    session_id = str(knowledge_item.get("sessionId", "")).strip()
    if not session_id:
        raise BenchmarkError(f"Knowledge item missing sessionId: {knowledge_path}")

    raw_event_path = resolve_raw_event_log(session_id, task_id)
    raw_event_count = validate_jsonl(raw_event_path)
    knowledge_steps = knowledge_item.get("steps", [])
    if not isinstance(knowledge_steps, list) or not knowledge_steps:
        raise BenchmarkError(f"Knowledge item has no steps: {knowledge_path}")

    legacy_reports = sorted((REPO_ROOT / "data/reports").rglob(f"*{task_id}*student-review.json"))
    legacy_feedback = sorted((REPO_ROOT / "data/feedback").rglob(f"{session_id}-{task_id}-teacher-feedback.jsonl"))
    context = knowledge_item.get("context", {})
    source = knowledge_item.get("source", {})

    return {
        "taskId": task_id,
        "sessionId": session_id,
        "knowledgePath": knowledge_path,
        "taskChunkPath": task_chunk_path,
        "rawEventPath": raw_event_path,
        "legacyStudentReviewPaths": legacy_reports,
        "legacyTeacherFeedbackPaths": legacy_feedback,
        "knowledgeStepCount": len(knowledge_steps),
        "rawEventCount": raw_event_count,
        "appName": str(context.get("appName", "")).strip(),
        "windowTitle": str(context.get("windowTitle", "")).strip(),
        "goal": str(knowledge_item.get("goal", "")).strip(),
        "boundaryReason": str(source.get("boundaryReason", "")).strip(),
        "startTimestamp": str(source.get("startTimestamp", "")).strip(),
        "endTimestamp": str(source.get("endTimestamp", "")).strip(),
    }


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
        task_id = str(case.get("taskId", "")).strip()
        category = str(case.get("category", "")).strip()
        title = str(case.get("title", "")).strip()
        if not case_id or not task_id or not category or not title:
            raise BenchmarkError(f"Catalog case[{index}] must define caseId/taskId/category/title.")
        if case_id in case_ids:
            raise BenchmarkError(f"Duplicate caseId in catalog: {case_id}")
        case_ids.add(case_id)
    return payload


def select_cases(catalog: dict[str, Any], case_ids: list[str], case_limit: int | None) -> list[dict[str, Any]]:
    selected = list(catalog["cases"])
    if case_ids:
        allowed = set(case_ids)
        selected = [case for case in selected if case["caseId"] in allowed]

    if case_limit is not None:
        selected = selected[: max(case_limit, 0)]

    if not selected:
        raise BenchmarkError("No benchmark cases selected.")
    return selected


def prepare_openclaw_executable() -> str:
    env = build_swift_env()
    build_command = [
        "swift",
        "build",
        "--package-path",
        repo_relative(PACKAGE_PATH),
        "--product",
        OPENCLAW_TARGET,
    ]
    require_success(run_command(build_command, env=env), "swift build OpenStaffOpenClawCLI")

    show_bin_command = [
        "swift",
        "build",
        "--package-path",
        repo_relative(PACKAGE_PATH),
        "--show-bin-path",
    ]
    show_bin_result = run_command(show_bin_command, env=env)
    require_success(show_bin_result, "swift build --show-bin-path")
    executable = Path(show_bin_result.stdout.strip()) / OPENCLAW_TARGET
    if not executable.exists():
        raise BenchmarkError(f"OpenClaw executable not found after build: {executable}")
    return repo_relative(executable)


def build_source_record(case: dict[str, Any], discovered: dict[str, Any]) -> dict[str, Any]:
    legacy_reports = [repo_relative(path) for path in discovered["legacyStudentReviewPaths"]]
    legacy_feedback = [repo_relative(path) for path in discovered["legacyTeacherFeedbackPaths"]]
    return {
        "schemaVersion": SOURCE_RECORD_SCHEMA_VERSION,
        "caseId": case["caseId"],
        "taskId": discovered["taskId"],
        "sessionId": discovered["sessionId"],
        "category": case["category"],
        "title": case["title"],
        "sourceArtifacts": {
            "rawEventLogPath": repo_relative(discovered["rawEventPath"]),
            "rawEventLogSha256": sha256_file(discovered["rawEventPath"]),
            "rawEventCount": discovered["rawEventCount"],
            "taskChunkPath": repo_relative(discovered["taskChunkPath"]),
            "taskChunkSha256": sha256_file(discovered["taskChunkPath"]),
            "knowledgeItemPath": repo_relative(discovered["knowledgePath"]),
            "knowledgeItemSha256": sha256_file(discovered["knowledgePath"]),
            "knowledgeStepCount": discovered["knowledgeStepCount"],
        },
        "legacyArtifacts": {
            "studentReviewPaths": legacy_reports,
            "teacherFeedbackPaths": legacy_feedback,
        },
        "context": {
            "appName": discovered["appName"],
            "windowTitle": discovered["windowTitle"],
            "goal": discovered["goal"],
            "boundaryReason": discovered["boundaryReason"],
            "startTimestamp": discovered["startTimestamp"],
            "endTimestamp": discovered["endTimestamp"],
        },
        "tags": case.get("tags", []),
    }


def run_skill_mapper(case_output_dir: Path, case: dict[str, Any], discovered: dict[str, Any]) -> tuple[str, subprocess.CompletedProcess[str]]:
    skill_name = slugify(f"benchmark-{case['caseId']}", "benchmark-skill")
    command = [
        sys.executable,
        repo_relative(MAPPER_PATH),
        "--knowledge-item",
        repo_relative(discovered["knowledgePath"]),
        "--llm-output",
        repo_relative(DEFAULT_LLM_OUTPUT_PATH),
        "--skills-root",
        repo_relative(case_output_dir),
        "--skill-name",
        skill_name,
        "--overwrite",
    ]
    completed = run_command(command)
    require_success(completed, f"skill mapper for {case['caseId']}")
    skill_dir = case_output_dir / skill_name
    if not (skill_dir / "SKILL.md").exists() or not (skill_dir / "openstaff-skill.json").exists():
        raise BenchmarkError(f"Skill mapper did not generate a valid skill directory: {skill_dir}")
    return repo_relative(skill_dir), completed


def run_preflight(skill_dir: str) -> tuple[dict[str, Any], subprocess.CompletedProcess[str]]:
    command = [
        sys.executable,
        repo_relative(PREFLIGHT_PATH),
        "--skill-dir",
        skill_dir,
        "--json",
    ]
    completed = run_command(command)
    if completed.returncode not in {0, 1}:
        require_success(completed, f"skill preflight for {skill_dir}")
    report = extract_last_json_object(completed.stdout)
    if not isinstance(report, dict):
        raise BenchmarkError(f"Skill preflight returned non-object JSON for {skill_dir}.")
    return normalize_path_fields(report), completed


def run_openclaw(executable_path: str, skill_dir: str, logs_root: str) -> tuple[dict[str, Any], subprocess.CompletedProcess[str]]:
    command = [
        executable_path,
        "--skill-dir",
        skill_dir,
        "--logs-root",
        logs_root,
        "--teacher-confirmed",
        "--json-result",
    ]
    completed = run_command(command, env=build_swift_env())
    if completed.returncode not in {0, 2}:
        require_success(completed, f"OpenClaw execution for {skill_dir}")
    payload = extract_last_json_object(completed.stdout)
    if not isinstance(payload, dict):
        raise BenchmarkError(f"OpenClaw execution returned non-object JSON for {skill_dir}.")
    return normalize_path_fields(payload), completed


def build_review_result(
    *,
    case: dict[str, Any],
    discovered: dict[str, Any],
    preflight: dict[str, Any],
    execution: dict[str, Any] | None,
    skip_openclaw: bool,
    skill_dir: str,
) -> dict[str, Any]:
    expected = case.get("expected", {}) if isinstance(case.get("expected"), dict) else {}
    expected_preflight_status = str(expected.get("preflightStatus", "")).strip() or None
    expected_execution_status = str(expected.get("executionStatus", "")).strip() or None
    preflight_status = str(preflight.get("status", "unknown")).strip() or "unknown"
    execution_status = "skipped"
    mismatches: list[str] = []

    summary_parts = [
        f"skill preflight={preflight_status}",
    ]

    if execution is not None:
        execution_status = str(execution.get("status", "unknown")).strip() or "unknown"
        succeeded_steps = int(execution.get("succeededSteps", 0) or 0)
        total_steps = int(execution.get("totalSteps", 0) or 0)
        summary_parts.append(f"runtime={execution_status}")
        summary_parts.append(f"steps={succeeded_steps}/{total_steps}")
    elif skip_openclaw:
        summary_parts.append("runtime=skipped")

    if expected_preflight_status:
        summary_parts.append(f"expectedPreflight={expected_preflight_status}")
        if preflight_status != expected_preflight_status:
            mismatches.append(
                f"Observed preflightStatus={preflight_status}, expected {expected_preflight_status}."
            )
    elif preflight_status == "failed":
        mismatches.append("Preflight failed without an expected baseline override.")

    if execution is not None and expected_execution_status:
        summary_parts.append(f"expectedRuntime={expected_execution_status}")
        if execution_status != expected_execution_status:
            mismatches.append(
                f"Observed executionStatus={execution_status}, expected {expected_execution_status}."
            )
    elif execution is not None and not expected_execution_status and execution_status != "succeeded":
        mismatches.append("Runtime did not succeed and the catalog does not define an expected executionStatus.")

    passed = len(mismatches) == 0
    decision = "approved" if passed else "rejected"
    notes: list[str] = []
    if preflight_status == "needs_teacher_confirmation":
        notes.append("Benchmark runner injects teacher confirmation to validate deterministic runtime execution for confirmation-gated skills.")
    if discovered["legacyStudentReviewPaths"]:
        notes.append(f"Found {len(discovered['legacyStudentReviewPaths'])} legacy student review artifact(s).")
    if discovered["legacyTeacherFeedbackPaths"]:
        notes.append(f"Found {len(discovered['legacyTeacherFeedbackPaths'])} legacy teacher feedback artifact(s).")
    notes.extend(mismatches)

    payload = {
        "schemaVersion": REVIEW_SCHEMA_VERSION,
        "caseId": case["caseId"],
        "taskId": discovered["taskId"],
        "sessionId": discovered["sessionId"],
        "category": case["category"],
        "title": case["title"],
        "reviewedAt": now_iso(),
        "reviewer": "benchmark-regression",
        "decision": decision,
        "passed": passed,
        "summary": "; ".join(summary_parts),
        "notes": notes,
        "artifacts": {
            "skillDirectoryPath": skill_dir,
            "expectedPreflightStatus": expected_preflight_status,
            "preflightStatus": preflight_status,
            "expectedExecutionStatus": expected_execution_status if execution is not None else ("skipped" if skip_openclaw else None),
            "executionStatus": execution_status,
        },
    }
    if execution is not None and isinstance(execution.get("review"), dict):
        payload["artifacts"]["executionLogPath"] = execution["review"].get("logFilePath", "")
    return payload


def process_case(
    case: dict[str, Any],
    benchmark_root: Path,
    *,
    openclaw_executable: str | None,
    skip_openclaw: bool,
) -> dict[str, Any]:
    case_output_dir = benchmark_root / "generated" / case["caseId"]
    case_output_dir.mkdir(parents=True, exist_ok=True)

    discovered = discover_case_sources(case["taskId"])
    source_record = build_source_record(case, discovered)
    source_record_path = case_output_dir / "source-record.json"
    write_json(source_record_path, source_record)

    skill_dir, mapper_result = run_skill_mapper(case_output_dir, case, discovered)
    preflight_report, preflight_result = run_preflight(skill_dir)
    preflight_report_path = case_output_dir / "skill-preflight.json"
    write_json(preflight_report_path, preflight_report)

    execution_payload: dict[str, Any] | None = None
    execution_report_path: Path | None = None
    if not skip_openclaw:
        if openclaw_executable is None:
            raise BenchmarkError("OpenClaw executable was not prepared.")
        logs_root = repo_relative(case_output_dir / "logs")
        execution_payload, _ = run_openclaw(openclaw_executable, skill_dir, logs_root)
        execution_report_path = case_output_dir / "execution-result.json"
        write_json(execution_report_path, execution_payload)

    review_result = build_review_result(
        case=case,
        discovered=discovered,
        preflight=preflight_report,
        execution=execution_payload,
        skip_openclaw=skip_openclaw,
        skill_dir=skill_dir,
    )
    review_result_path = case_output_dir / "review-result.json"
    write_json(review_result_path, review_result)

    case_report = {
        "schemaVersion": CASE_REPORT_SCHEMA_VERSION,
        "caseId": case["caseId"],
        "taskId": discovered["taskId"],
        "sessionId": discovered["sessionId"],
        "category": case["category"],
        "title": case["title"],
        "passed": review_result["passed"],
        "source": {
            "appName": discovered["appName"],
            "windowTitle": discovered["windowTitle"],
            "goal": discovered["goal"],
            "knowledgeStepCount": discovered["knowledgeStepCount"],
            "rawEventCount": discovered["rawEventCount"],
        },
        "artifacts": {
            "sourceRecordPath": repo_relative(source_record_path),
            "skillDirectoryPath": skill_dir,
            "skillPreflightPath": repo_relative(preflight_report_path),
            "executionResultPath": repo_relative(execution_report_path) if execution_report_path else None,
            "reviewResultPath": repo_relative(review_result_path),
        },
        "results": {
            "expectedSkillPreflightStatus": case.get("expected", {}).get("preflightStatus"),
            "skillMapperExitCode": mapper_result.returncode,
            "skillPreflightExitCode": preflight_result.returncode,
            "skillPreflightStatus": preflight_report.get("status"),
            "expectedExecutionStatus": case.get("expected", {}).get("executionStatus"),
            "executionStatus": execution_payload.get("status") if execution_payload else "skipped",
            "reviewDecision": review_result["decision"],
        },
        "tags": case.get("tags", []),
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
    skip_openclaw: bool,
) -> dict[str, Any]:
    failed_cases = [case["caseId"] for case in case_reports if not case["passed"]]
    category_counts = Counter(case["category"] for case in case_reports)
    return {
        "schemaVersion": MANIFEST_SCHEMA_VERSION,
        "benchmarkId": benchmark_id,
        "generatedAt": now_iso(),
        "benchmarkRoot": repo_relative(benchmark_root),
        "catalogPath": repo_relative(catalog_path),
        "skipOpenClaw": skip_openclaw,
        "totalCases": len(case_reports),
        "passedCases": len(case_reports) - len(failed_cases),
        "failedCases": failed_cases,
        "categoryCounts": dict(sorted(category_counts.items())),
        "cases": case_reports,
    }


def main() -> int:
    args = parse_args()
    benchmark_root = args.benchmark_root.resolve()
    benchmark_root.mkdir(parents=True, exist_ok=True)

    catalog = load_catalog(args.catalog.resolve())
    selected_cases = select_cases(catalog, args.case_id, args.case_limit)
    openclaw_executable = None
    if not args.skip_openclaw:
        openclaw_executable = normalize_path_value(args.openclaw_executable) if args.openclaw_executable else prepare_openclaw_executable()

    case_reports: list[dict[str, Any]] = []
    for case in selected_cases:
        print(f"[benchmark] case={case['caseId']} task={case['taskId']}")
        case_reports.append(
            process_case(
                case,
                benchmark_root,
                openclaw_executable=openclaw_executable,
                skip_openclaw=args.skip_openclaw,
            )
        )

    benchmark_id = str(catalog.get("benchmarkId", "personal-desktop-benchmark")).strip() or "personal-desktop-benchmark"
    manifest = build_manifest(
        benchmark_root=benchmark_root,
        catalog_path=args.catalog.resolve(),
        benchmark_id=benchmark_id,
        case_reports=case_reports,
        skip_openclaw=args.skip_openclaw,
    )
    report_path = args.report.resolve() if args.report else benchmark_root / "manifest.json"
    write_json(report_path, manifest)

    print(f"[benchmark] total={manifest['totalCases']} passed={manifest['passedCases']} failed={len(manifest['failedCases'])}")
    print(f"[benchmark] manifest={repo_relative(report_path)}")
    return 0 if not manifest["failedCases"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
