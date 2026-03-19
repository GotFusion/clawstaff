#!/usr/bin/env python3
"""
Run the OpenStaff Personal Preference Benchmark corpus.
"""

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
DEFAULT_BENCHMARK_ROOT = REPO_ROOT / "data/benchmarks/personal-preference"
DEFAULT_CATALOG_PATH = DEFAULT_BENCHMARK_ROOT / "catalog.json"
MANIFEST_SCHEMA_VERSION = "openstaff.personal-preference-benchmark.manifest.v0"
CASE_REPORT_SCHEMA_VERSION = "openstaff.personal-preference-benchmark.case-report.v0"
SOURCE_RECORD_SCHEMA_VERSION = "openstaff.personal-preference-benchmark.source-record.v0"
REVIEW_SCHEMA_VERSION = "openstaff.personal-preference-benchmark.review.v0"
XCODE_DEVELOPER_DIR = Path("/Applications/Xcode.app/Contents/Developer")
MODULE_PRODUCTS = {
    "assist": "OpenStaffAssistCLI",
    "student": "OpenStaffStudentCLI",
    "repair": "OpenStaffReplayVerifyCLI",
    "review": "OpenStaffExecutionReviewCLI",
}
MODULE_EXPECTED_KEYS = {
    "assist": [
        "finalStatus",
        "selectedKnowledgeItemId",
        "predictorVersion",
        "actionInstruction",
        "appliedRuleIds",
    ],
    "student": [
        "finalStatus",
        "selectedKnowledgeItemId",
        "strategy",
        "plannerVersion",
        "executionStyle",
        "failureRecoveryPreference",
        "appliedRuleIds",
    ],
    "repair": [
        "driftStatus",
        "dominantDriftKind",
        "selectedActionType",
        "appliedRuleIds",
    ],
    "review": [
        "topAction",
        "suggestedNote",
        "appliedRuleIds",
    ],
}


class BenchmarkError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the OpenStaff Personal Preference Benchmark.")
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
        "--assist-executable",
        type=str,
        help="Optional prebuilt OpenStaffAssistCLI executable path.",
    )
    parser.add_argument(
        "--student-executable",
        type=str,
        help="Optional prebuilt OpenStaffStudentCLI executable path.",
    )
    parser.add_argument(
        "--replay-verify-executable",
        type=str,
        help="Optional prebuilt OpenStaffReplayVerifyCLI executable path.",
    )
    parser.add_argument(
        "--review-executable",
        type=str,
        help="Optional prebuilt OpenStaffExecutionReviewCLI executable path.",
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


def normalize_path_fields(payload: Any) -> Any:
    if isinstance(payload, dict):
        normalized: dict[str, Any] = {}
        for key, value in payload.items():
            if isinstance(value, str) and (key.endswith("Path") or key.endswith("DirectoryPath")):
                normalized[key] = repo_relative(Path(value)) if Path(value).exists() else value
            else:
                normalized[key] = normalize_path_fields(value)
        return normalized
    if isinstance(payload, list):
        return [normalize_path_fields(item) for item in payload]
    return payload


def resolve_executable(
    product: str,
    explicit_path: str | None,
    *,
    swift_env: dict[str, str],
) -> Path:
    if explicit_path:
        path = Path(explicit_path)
        if not path.exists():
            raise BenchmarkError(f"Executable path does not exist for {product}: {path}")
        return path.resolve()

    default_path = PACKAGE_PATH / ".build" / "debug" / product
    if default_path.exists():
        return default_path.resolve()

    completed = run_command(
        ["swift", "build", "--package-path", str(PACKAGE_PATH), "--product", product],
        env=swift_env,
    )
    require_success(completed, f"swift build {product}")
    if not default_path.exists():
        raise BenchmarkError(f"Built product not found: {default_path}")
    return default_path.resolve()


def select_cases(catalog: dict[str, Any], args: argparse.Namespace) -> list[dict[str, Any]]:
    cases = list(catalog.get("cases", []))
    if args.case_id:
        requested = set(args.case_id)
        cases = [case for case in cases if case["caseId"] in requested]
        found = {case["caseId"] for case in cases}
        missing = sorted(requested - found)
        if missing:
            raise BenchmarkError(f"Unknown benchmark case ID(s): {', '.join(missing)}")

    if args.case_limit is not None:
        cases = cases[: max(0, args.case_limit)]

    if not cases:
        raise BenchmarkError("No benchmark cases selected.")
    return cases


def iso_timestamp(index: int) -> str:
    hour = 10 + (index % 10)
    minute = (index * 3) % 60
    second = (index * 7) % 60
    return f"2026-03-19T{hour:02d}:{minute:02d}:{second:02d}.000Z"


def title_from_instruction(instruction: str, fallback: str) -> str:
    text = instruction.strip()
    for prefix in ["点击 ", "按下 ", "打开 ", "输入 ", "确认 ", "选择 "]:
        if text.startswith(prefix):
            candidate = text[len(prefix) :].strip()
            if candidate:
                return candidate
    return fallback


def build_knowledge_item(
    spec: dict[str, Any],
    *,
    default_goal: str,
    default_app_name: str,
    default_app_bundle_id: str,
    default_window_title: str,
    default_session_id: str,
    created_at: str,
) -> dict[str, Any]:
    steps = []
    instructions = spec["stepInstructions"]
    add_targets = bool(spec.get("addSemanticTargets"))
    for index, instruction in enumerate(instructions, start=1):
        step: dict[str, Any] = {
            "stepId": f"step-{index:03d}",
            "instruction": instruction,
            "sourceEventIds": [f"evt-{spec['knowledgeItemId']}-{index:03d}"],
        }
        if add_targets:
            element_title = title_from_instruction(instruction, f"Action {index}")
            step["target"] = {
                "semanticTargets": [
                    {
                        "locatorType": "roleAndTitle",
                        "appBundleId": spec.get("appBundleId", default_app_bundle_id),
                        "windowTitlePattern": "^"
                        + (spec.get("windowTitle", default_window_title).replace("\\", "\\\\").replace("^", "\\^").replace("$", "\\$"))
                        + "$",
                        "elementRole": "AXButton",
                        "elementTitle": element_title,
                        "confidence": 0.92,
                        "source": "capture",
                    }
                ],
                "preferredLocatorType": "roleAndTitle",
            }
        steps.append(step)

    return {
        "schemaVersion": "knowledge.item.v0",
        "knowledgeItemId": spec["knowledgeItemId"],
        "taskId": spec["taskId"],
        "sessionId": spec.get("sessionId", default_session_id),
        "goal": spec.get("goal", default_goal),
        "summary": spec.get("summary", spec.get("goal", default_goal)),
        "steps": steps,
        "context": {
            "appName": spec.get("appName", default_app_name),
            "appBundleId": spec.get("appBundleId", default_app_bundle_id),
            "windowTitle": spec.get("windowTitle", default_window_title),
            "windowId": None,
        },
        "constraints": spec.get("constraints", []),
        "source": {
            "taskChunkSchemaVersion": "task.chunk.v0",
            "startTimestamp": created_at,
            "endTimestamp": created_at,
            "eventCount": len(steps),
            "boundaryReason": "sessionEnd",
        },
        "createdAt": spec.get("createdAt", created_at),
        "generatorVersion": "rule-v0",
    }


def build_profile_snapshot(
    profile_id: str,
    module: str,
    profiles: dict[str, Any],
) -> dict[str, Any]:
    spec = profiles.get(profile_id)
    if not spec:
        raise BenchmarkError(f"Profile not found in catalog: {profile_id}")

    rules = spec.get("rules", [])
    active_rule_ids = [rule["ruleId"] for rule in rules]
    profile = {
        "schemaVersion": "openstaff.learning.preference-profile.v0",
        "profileVersion": profile_id,
        "activeRuleIds": active_rule_ids,
        "assistPreferences": rules if module == "assist" else [],
        "skillPreferences": [],
        "repairPreferences": rules if module == "repair" else [],
        "reviewPreferences": rules if module == "review" else [],
        "plannerPreferences": rules if module == "student" else [],
        "generatedAt": spec.get("generatedAt", "2026-03-19T10:00:00.000Z"),
    }
    return {
        "schemaVersion": "openstaff.learning.preference-profile-snapshot.v0",
        "profileVersion": profile_id,
        "profile": profile,
        "sourceRuleIds": active_rule_ids,
        "createdAt": spec.get("generatedAt", "2026-03-19T10:00:00.000Z"),
        "previousProfileVersion": None,
        "note": spec.get("note", spec.get("description")),
    }


def write_profile_snapshot(
    preferences_root: Path,
    profile_snapshot: dict[str, Any],
) -> Path:
    profiles_root = preferences_root / "profiles"
    profiles_root.mkdir(parents=True, exist_ok=True)
    profile_path = profiles_root / f"{profile_snapshot['profileVersion']}.json"
    latest_path = profiles_root / "latest.json"
    write_json(profile_path, profile_snapshot)
    write_json(
        latest_path,
        {
            "profileVersion": profile_snapshot["profileVersion"],
            "updatedAt": profile_snapshot["createdAt"],
        },
    )
    return profile_path


def write_knowledge_dir(
    root: Path,
    fixture: dict[str, Any],
    *,
    default_session_id: str,
    created_at: str,
) -> None:
    root.mkdir(parents=True, exist_ok=True)
    for candidate in fixture["candidates"]:
        payload = build_knowledge_item(
            candidate,
            default_goal=fixture["goal"],
            default_app_name=fixture["appName"],
            default_app_bundle_id=fixture["appBundleId"],
            default_window_title=fixture["windowTitle"],
            default_session_id=default_session_id,
            created_at=candidate.get("createdAt", created_at),
        )
        write_json(root / f"{payload['knowledgeItemId']}.json", payload)


def run_assist_case(
    case: dict[str, Any],
    case_dir: Path,
    profile_snapshot: dict[str, Any],
    executable: Path,
) -> dict[str, Any]:
    fixture = case["fixture"]
    preferences_root = case_dir / "preferences"
    knowledge_root = case_dir / "knowledge"
    logs_root = case_dir / "logs"
    timestamp = case.get("timestamp", "2026-03-19T10:00:00.000Z")

    write_profile_snapshot(preferences_root, profile_snapshot)
    write_knowledge_dir(
        knowledge_root,
        fixture,
        default_session_id=f"session-{case['caseId']}",
        created_at=timestamp,
    )

    command = [
        str(executable),
        "--knowledge-item",
        str(knowledge_root),
        "--preferences-root",
        str(preferences_root),
        "--from",
        "teaching",
        "--app-name",
        fixture["appName"],
        "--app-bundle-id",
        fixture["appBundleId"],
        "--window-title",
        fixture["windowTitle"],
        "--goal",
        fixture["goal"],
        "--completed-steps",
        str(fixture.get("completedSteps", 0)),
        "--auto-confirm",
        "yes",
        "--logs-root",
        str(logs_root),
        "--trace-id",
        f"trace-{case['caseId']}",
        "--timestamp",
        timestamp,
        "--json-result",
    ]
    if fixture.get("taskFamily"):
        command.extend(["--task-family", fixture["taskFamily"]])
    for recent_step in fixture.get("recentSteps", []):
        command.extend(["--recent-step", recent_step])

    completed = run_command(
        command,
        env={**os.environ, "OPENSTAFF_ENABLE_POLICY_ASSEMBLY_LOG": "1"},
    )
    require_success(completed, f"assist benchmark {case['caseId']}")
    payload = extract_last_json_object(completed.stdout)
    write_json(case_dir / "module-result.json", normalize_path_fields(payload))

    suggestion = payload.get("suggestion") or {}
    action = suggestion.get("action") or {}
    decision = suggestion.get("preferenceDecision") or {}
    return {
        "finalStatus": payload.get("finalStatus"),
        "selectedKnowledgeItemId": suggestion.get("knowledgeItemId"),
        "predictorVersion": suggestion.get("predictorVersion"),
        "actionInstruction": action.get("instruction"),
        "appliedRuleIds": sorted(decision.get("appliedRuleIds") or []),
    }


def run_student_case(
    case: dict[str, Any],
    case_dir: Path,
    profile_snapshot: dict[str, Any],
    executable: Path,
) -> dict[str, Any]:
    fixture = case["fixture"]
    preferences_root = case_dir / "preferences"
    knowledge_root = case_dir / "knowledge"
    logs_root = case_dir / "logs"
    reports_root = case_dir / "reports"
    timestamp = case.get("timestamp", "2026-03-19T10:00:00.000Z")

    write_profile_snapshot(preferences_root, profile_snapshot)
    write_knowledge_dir(
        knowledge_root,
        fixture,
        default_session_id=f"session-{case['caseId']}",
        created_at=timestamp,
    )

    command = [
        str(executable),
        "--goal",
        fixture["goal"],
        "--knowledge",
        str(knowledge_root),
        "--enable-preference-aware-planner",
        "--student-planner-benchmark-safe",
        "--preferences-root",
        str(preferences_root),
        "--logs-root",
        str(logs_root),
        "--reports-root",
        str(reports_root),
        "--trace-id",
        f"trace-{case['caseId']}",
        "--timestamp",
        timestamp,
        "--json-result",
    ]
    if fixture.get("preferredKnowledgeItemId"):
        command.extend(["--preferred-knowledge-item-id", fixture["preferredKnowledgeItemId"]])

    completed = run_command(
        command,
        env={**os.environ, "OPENSTAFF_ENABLE_POLICY_ASSEMBLY_LOG": "1"},
    )
    require_success(completed, f"student benchmark {case['caseId']}")
    payload = extract_last_json_object(completed.stdout)
    write_json(case_dir / "module-result.json", normalize_path_fields(payload))

    plan = payload.get("plan") or {}
    decision = plan.get("preferenceDecision") or {}
    return {
        "finalStatus": payload.get("finalStatus"),
        "selectedKnowledgeItemId": plan.get("selectedKnowledgeItemId"),
        "strategy": plan.get("strategy"),
        "plannerVersion": plan.get("plannerVersion"),
        "executionStyle": decision.get("executionStyle"),
        "failureRecoveryPreference": decision.get("failureRecoveryPreference"),
        "appliedRuleIds": sorted(decision.get("appliedRuleIds") or []),
    }


def build_repair_skill_payload(fixture: dict[str, Any], profile_snapshot: dict[str, Any]) -> dict[str, Any]:
    return {
        "schemaVersion": "openstaff.openclaw-skill.v1",
        "skillName": fixture["skillName"],
        "knowledgeItemId": fixture.get("knowledgeItemId", "knowledge-001"),
        "taskId": fixture.get("taskId", "task-001"),
        "sessionId": fixture.get("sessionId", "session-001"),
        "llmOutputAccepted": True,
        "createdAt": fixture.get("timestamp", "2026-03-19T10:00:00.000Z"),
        "mappedOutput": {
            "objective": fixture["goal"],
            "context": {
                "appName": fixture["appName"],
                "appBundleId": fixture["appBundleId"],
                "windowTitle": fixture["windowTitle"],
            },
            "executionPlan": {
                "requiresTeacherConfirmation": False,
                "steps": [
                    {
                        "stepId": "step-001",
                        "actionType": "click",
                        "instruction": fixture["skillInstruction"],
                        "target": fixture["skillTargetTitle"],
                        "sourceEventIds": ["evt-001"],
                    }
                ],
                "completionCriteria": {
                    "expectedStepCount": 1,
                    "requiredFrontmostAppBundleId": fixture["appBundleId"],
                },
            },
            "safetyNotes": [],
            "confidence": 0.9,
        },
        "provenance": {
            "skillBuild": {
                "repairVersion": fixture.get("repairVersion", 2),
                "preferenceProfileVersion": profile_snapshot["profileVersion"],
                "appliedPreferenceRuleIds": profile_snapshot["sourceRuleIds"],
                "preferenceSummary": fixture.get("preferenceSummary"),
                "taskFamily": fixture.get("taskFamily"),
                "skillFamily": fixture.get("skillFamily"),
            },
            "stepMappings": [
                {
                    "skillStepId": "step-001",
                    "knowledgeStepId": "teacher-step-001",
                    "instruction": fixture["skillInstruction"],
                    "sourceEventIds": ["evt-001"],
                    "preferredLocatorType": "textAnchor",
                    "coordinate": {
                        "x": 320,
                        "y": 240,
                        "coordinateSpace": "screen",
                    },
                    "semanticTargets": [
                        {
                            "locatorType": "textAnchor",
                            "appBundleId": fixture["appBundleId"],
                            "windowTitlePattern": "^" + fixture["windowTitle"] + "$",
                            "elementRole": "AXButton",
                            "elementTitle": fixture["skillTargetTitle"],
                            "elementIdentifier": fixture.get("elementIdentifier", "primary-action"),
                            "textAnchor": fixture["skillTargetTitle"],
                            "confidence": 0.91,
                            "source": "capture",
                        }
                    ],
                }
            ],
        },
    }


def build_replay_snapshot(fixture: dict[str, Any]) -> dict[str, Any]:
    visible_title = fixture.get("snapshotVisibleTitle", fixture["skillTargetTitle"])
    return {
        "capturedAt": fixture.get("timestamp", "2026-03-19T10:05:00.000Z"),
        "appName": fixture["appName"],
        "appBundleId": fixture["appBundleId"],
        "windowTitle": fixture["windowTitle"],
        "windowId": "window-1",
        "windowSignature": {
            "signature": f"signature-{fixture['skillName']}",
            "signatureVersion": "window-v1",
            "normalizedTitle": fixture["windowTitle"].lower(),
            "role": "AXWindow",
            "subrole": "AXStandardWindow",
            "sizeBucket": "12x8",
        },
        "focusedElement": {
            "axPath": "AXWindow/AXButton[0]",
            "role": "AXButton",
            "title": fixture.get("snapshotFocusedTitle", visible_title),
            "identifier": fixture.get("elementIdentifier", "primary-action"),
            "boundingRect": {
                "x": 220,
                "y": 100,
                "width": 80,
                "height": 30,
                "coordinateSpace": "screen",
            },
        },
        "visibleElements": [
            {
                "axPath": "AXWindow/AXButton[0]",
                "role": "AXButton",
                "title": visible_title,
                "identifier": fixture.get("elementIdentifier", "primary-action"),
                "boundingRect": {
                    "x": 220,
                    "y": 100,
                    "width": 80,
                    "height": 30,
                    "coordinateSpace": "screen",
                },
            }
        ],
        "screenshotAnchors": [],
        "captureDiagnostics": [],
    }


def run_repair_case(
    case: dict[str, Any],
    case_dir: Path,
    profile_snapshot: dict[str, Any],
    executable: Path,
) -> dict[str, Any]:
    fixture = case["fixture"]
    preferences_root = case_dir / "preferences"
    skill_dir = case_dir / fixture["skillName"]
    snapshot_path = case_dir / "snapshot.json"

    write_profile_snapshot(preferences_root, profile_snapshot)
    skill_dir.mkdir(parents=True, exist_ok=True)
    write_json(skill_dir / "openstaff-skill.json", build_repair_skill_payload(fixture, profile_snapshot))
    write_json(snapshot_path, build_replay_snapshot(fixture))

    command = [
        str(executable),
        "--skill-dir",
        str(skill_dir),
        "--snapshot",
        str(snapshot_path),
        "--preferences-root",
        str(preferences_root),
        "--json",
    ]
    completed = run_command(
        command,
        env={**os.environ, "OPENSTAFF_ENABLE_POLICY_ASSEMBLY_LOG": "1"},
    )
    if completed.returncode not in {0, 2}:
        require_success(completed, f"repair benchmark {case['caseId']}")
    payload = extract_last_json_object(completed.stdout)
    write_json(case_dir / "module-result.json", normalize_path_fields(payload))

    repair_plan = payload.get("repairPlan") or {}
    preference_decision = repair_plan.get("preferenceDecision") or {}
    first_action = (repair_plan.get("actions") or [{}])[0]
    drift_report = payload.get("driftReport") or {}
    return {
        "driftStatus": drift_report.get("status"),
        "dominantDriftKind": drift_report.get("dominantDriftKind"),
        "selectedActionType": first_action.get("type"),
        "appliedRuleIds": sorted(preference_decision.get("appliedRuleIds") or []),
    }


def build_review_scenario(
    case: dict[str, Any],
    profile_snapshot: dict[str, Any],
) -> dict[str, Any]:
    fixture = case["fixture"]
    return {
        "scenarioId": case["caseId"],
        "traceId": f"trace-{case['caseId']}",
        "sessionId": fixture.get("sessionId", f"session-{case['caseId']}"),
        "taskId": fixture.get("taskId", f"task-{case['caseId']}"),
        "timestamp": case.get("timestamp", "2026-03-19T10:00:00.000Z"),
        "goal": fixture["goal"],
        "summary": fixture["summary"],
        "appName": fixture["appName"],
        "appBundleId": fixture["appBundleId"],
        "windowTitle": fixture["windowTitle"],
        "taskFamily": fixture.get("taskFamily"),
        "skillFamily": fixture.get("skillFamily"),
        "repairVersion": fixture.get("repairVersion", 2),
        "teacherSteps": fixture["teacherSteps"],
        "skillSteps": fixture["skillSteps"],
        "failedLog": fixture["failedLog"],
        "preferenceSnapshot": profile_snapshot,
    }


def run_review_case(
    case: dict[str, Any],
    case_dir: Path,
    profile_snapshot: dict[str, Any],
    executable: Path,
) -> dict[str, Any]:
    scenario_path = case_dir / "review-scenario.json"
    write_json(scenario_path, build_review_scenario(case, profile_snapshot))
    command = [
        str(executable),
        "--scenario",
        str(scenario_path),
        "--json",
    ]
    completed = run_command(command)
    require_success(completed, f"review benchmark {case['caseId']}")
    payload = extract_last_json_object(completed.stdout)
    write_json(case_dir / "module-result.json", normalize_path_fields(payload))
    top = payload.get("topSuggestion") or {}
    return {
        "topAction": top.get("action"),
        "suggestedNote": top.get("suggestedNote"),
        "appliedRuleIds": sorted(top.get("appliedRuleIds") or []),
    }


def compare_expected(module: str, expected: dict[str, Any], actual: dict[str, Any]) -> tuple[bool, list[str]]:
    mismatches: list[str] = []
    for key in MODULE_EXPECTED_KEYS[module]:
        if key not in expected:
            continue
        expected_value = expected.get(key)
        actual_value = actual.get(key)
        if isinstance(expected_value, list):
            expected_value = sorted(expected_value)
        if isinstance(actual_value, list):
            actual_value = sorted(actual_value)
        if expected_value != actual_value:
            mismatches.append(f"{key}: expected {expected_value!r}, got {actual_value!r}")
    return len(mismatches) == 0, mismatches


def build_source_record(
    case: dict[str, Any],
    case_dir: Path,
    *,
    catalog_path: Path,
) -> dict[str, Any]:
    anchors = []
    for anchor in case.get("sourceAnchors", []):
        path = REPO_ROOT / anchor["path"]
        if not path.exists():
            raise BenchmarkError(f"Source anchor missing for {case['caseId']}: {path}")
        anchors.append(
            {
                "kind": anchor["kind"],
                "path": repo_relative(path),
                "sha256": sha256_file(path),
            }
        )

    payload = {
        "schemaVersion": SOURCE_RECORD_SCHEMA_VERSION,
        "caseId": case["caseId"],
        "module": case["module"],
        "preferenceCategory": case["preferenceCategory"],
        "sourceType": case["sourceType"],
        "derivedFromCaseId": case.get("derivedFromCaseId"),
        "catalogPath": repo_relative(catalog_path),
        "catalogSha256": sha256_file(catalog_path),
        "profileId": case["profileId"],
        "sourceAnchors": anchors,
        "generatedAt": now_iso(),
    }
    write_json(case_dir / "source-record.json", payload)
    return payload


def run_case(
    case: dict[str, Any],
    profiles: dict[str, Any],
    benchmark_root: Path,
    executables: dict[str, Path],
    *,
    catalog_path: Path,
) -> dict[str, Any]:
    case_dir = benchmark_root / "generated" / case["caseId"]
    case_dir.mkdir(parents=True, exist_ok=True)
    build_source_record(case, case_dir, catalog_path=catalog_path)
    profile_snapshot = build_profile_snapshot(case["profileId"], case["module"], profiles)
    write_json(case_dir / "profile-snapshot.json", profile_snapshot)

    if case["module"] == "assist":
        actual = run_assist_case(case, case_dir, profile_snapshot, executables["assist"])
    elif case["module"] == "student":
        actual = run_student_case(case, case_dir, profile_snapshot, executables["student"])
    elif case["module"] == "repair":
        actual = run_repair_case(case, case_dir, profile_snapshot, executables["repair"])
    elif case["module"] == "review":
        actual = run_review_case(case, case_dir, profile_snapshot, executables["review"])
    else:
        raise BenchmarkError(f"Unsupported benchmark module: {case['module']}")

    passed, mismatches = compare_expected(case["module"], case["expected"], actual)
    review_result = {
        "schemaVersion": REVIEW_SCHEMA_VERSION,
        "caseId": case["caseId"],
        "module": case["module"],
        "passed": passed,
        "mismatches": mismatches,
        "generatedAt": now_iso(),
    }
    case_report = {
        "schemaVersion": CASE_REPORT_SCHEMA_VERSION,
        "caseId": case["caseId"],
        "title": case["title"],
        "module": case["module"],
        "preferenceCategory": case["preferenceCategory"],
        "sourceType": case["sourceType"],
        "profileId": case["profileId"],
        "expected": case["expected"],
        "actual": actual,
        "passed": passed,
        "mismatches": mismatches,
        "generatedAt": now_iso(),
    }
    write_json(case_dir / "review-result.json", review_result)
    write_json(case_dir / "case-report.json", case_report)
    return case_report


def aggregate_metrics(case_reports: list[dict[str, Any]]) -> dict[str, Any]:
    total = len(case_reports)
    passed = sum(1 for report in case_reports if report["passed"])
    by_category = Counter(report["preferenceCategory"] for report in case_reports)
    passed_by_category = Counter(
        report["preferenceCategory"] for report in case_reports if report["passed"]
    )
    by_module = Counter(report["module"] for report in case_reports)
    passed_by_module = Counter(report["module"] for report in case_reports if report["passed"])

    category_rates = {
        category: round(passed_by_category.get(category, 0) / count, 4)
        for category, count in sorted(by_category.items())
    }
    module_rates = {
        module: round(passed_by_module.get(module, 0) / count, 4)
        for module, count in sorted(by_module.items())
    }
    return {
        "preferenceMatchRate": round(passed / total, 4) if total else 0,
        "matchRateByCategory": category_rates,
        "matchRateByModule": module_rates,
        "caseCountByCategory": dict(sorted(by_category.items())),
        "caseCountByModule": dict(sorted(by_module.items())),
    }


def main() -> int:
    args = parse_args()
    catalog = read_json(args.catalog)
    cases = select_cases(catalog, args)
    profiles = catalog.get("profiles", {})
    benchmark_root = args.benchmark_root.resolve()
    report_path = args.report.resolve() if args.report else benchmark_root / "manifest.json"
    benchmark_root.mkdir(parents=True, exist_ok=True)

    swift_env = build_swift_env()
    modules_needed = {case["module"] for case in cases}
    executables: dict[str, Path] = {}
    explicit_paths = {
        "assist": args.assist_executable,
        "student": args.student_executable,
        "repair": args.replay_verify_executable,
        "review": args.review_executable,
    }
    for module in sorted(modules_needed):
        executables[module] = resolve_executable(
            MODULE_PRODUCTS[module],
            explicit_paths.get(module),
            swift_env=swift_env,
        )

    case_reports = [
        run_case(
            case,
            profiles,
            benchmark_root,
            executables,
            catalog_path=args.catalog.resolve(),
        )
        for case in cases
    ]
    failed_cases = [report["caseId"] for report in case_reports if not report["passed"]]
    metrics = aggregate_metrics(case_reports)
    manifest = {
        "schemaVersion": MANIFEST_SCHEMA_VERSION,
        "benchmarkId": catalog.get("benchmarkId"),
        "generatedAt": now_iso(),
        "catalogPath": repo_relative(args.catalog.resolve()),
        "totalCases": len(case_reports),
        "passedCases": len(case_reports) - len(failed_cases),
        "failedCases": failed_cases,
        "metrics": metrics,
        "cases": case_reports,
    }
    write_json(report_path, manifest)

    print(
        "Personal Preference Benchmark finished. "
        f"passed={manifest['passedCases']}/{manifest['totalCases']} "
        f"report={report_path}"
    )
    if failed_cases:
        for case_id in failed_cases:
            print(f"FAILED {case_id}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
