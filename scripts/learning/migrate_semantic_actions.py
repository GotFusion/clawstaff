#!/usr/bin/env python3
"""Create or rollback the semantic action store and backfill actions from InteractionTurn."""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime
import json
from pathlib import Path
import re
from typing import Any

from semantic_action_store import (
    SCHEMA_VERSION,
    SemanticActionAssertionRecord,
    SemanticActionExecutionLogRecord,
    SemanticActionMigrationManager,
    SemanticActionRecord,
    SemanticActionRepository,
    SemanticActionTargetRecord,
)
from semantic_action_builder import build_actions_for_task_chunk, read_jsonl


REPO_ROOT = Path(__file__).resolve().parents[2]
HISTORICAL_REASON_NOT_NEEDED = "SEM301-NOT-NEEDED-ALREADY-SEMANTIC"
HISTORICAL_REASON_AUTO_CONVERTED = "SEM301-AUTO-CONVERTED-FROM-RAW-EVENTS"
HISTORICAL_REASON_MISSING_RAW_EVENT_LOG = "SEM301-MISSING-RAW-EVENT-LOG"
HISTORICAL_REASON_MISSING_TASK_CHUNK = "SEM301-MISSING-TASK-CHUNK"
HISTORICAL_REASON_SOURCE_EVENTS_MISSING = "SEM301-SOURCE-EVENTS-MISSING"
HISTORICAL_REASON_NO_MATCH = "SEM301-NO-HISTORICAL-MATCH"
HISTORICAL_REASON_COORDINATE_ONLY = "SEM301-RECOVERED-COORDINATE-ONLY"
HISTORICAL_REASON_REQUIRES_MANUAL_REVIEW = "SEM301-RECOVERED-REQUIRES-MANUAL-REVIEW"


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def deep_copy_json(value: Any) -> Any:
    return json.loads(json.dumps(value, ensure_ascii=False))


def repo_relative_or_abs(path: Path, workspace_root: Path) -> str:
    try:
        return path.resolve().relative_to(workspace_root.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def resolve_path(raw_path: str | None, workspace_root: Path) -> Path | None:
    if not raw_path:
        return None
    path = Path(raw_path)
    if path.is_absolute():
        return path
    return workspace_root / path


def exact_window_title_pattern(window_title: str | None) -> str | None:
    if not isinstance(window_title, str) or not window_title.strip():
        return None
    return f"^{re.escape(window_title.strip())}$"


def parse_iso_timestamp(value: str | None) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def duration_millis(started_at: str | None, ended_at: str | None) -> int | None:
    started = parse_iso_timestamp(started_at)
    ended = parse_iso_timestamp(ended_at)
    if started is None or ended is None:
        return None
    delta = ended - started
    return max(int(delta.total_seconds() * 1000), 0)


def normalize_action_type(raw: str | None) -> str | None:
    if not isinstance(raw, str):
        return None
    normalized = raw.strip().lower().replace("-", "_").replace(" ", "_")
    mapping = {
        "click": "click",
        "leftclick": "click",
        "doubleclick": "click",
        "rightclick": "click",
        "input": "type",
        "type": "type",
        "shortcut": "shortcut",
        "switchapp": "switch_app",
        "switch_app": "switch_app",
        "openapp": "switch_app",
        "open_app": "switch_app",
        "launchapp": "switch_app",
        "launch_app": "switch_app",
        "focuswindow": "focus_window",
        "focus_window": "focus_window",
        "drag": "drag",
        "dragdrop": "drag",
        "drag_and_drop": "drag",
    }
    return mapping.get(normalized)


def infer_action_type(turn: dict[str, Any], execution_step: dict[str, Any] | None) -> str:
    inferred = normalize_action_type((execution_step or {}).get("actionType"))
    if inferred:
        return inferred

    instruction = " ".join(
        [
            str((turn.get("stepReference") or {}).get("instruction") or ""),
            str(turn.get("actionSummary") or ""),
        ]
    ).lower()

    patterns = [
        ("switch_app", ("switch app", "switch_app", "切换应用", "打开应用", "launch app")),
        ("focus_window", ("focus window", "focus_window", "聚焦窗口", "切换窗口")),
        ("drag", ("drag", "拖动", "拖拽")),
        ("shortcut", ("shortcut", "快捷键", "按回车", "按 enter", "按 return")),
        ("type", ("input", "type", "输入", "键入")),
        ("click", ("click", "点击", "点按")),
    ]
    for action_type, tokens in patterns:
        if any(token in instruction for token in tokens):
            return action_type

    return "click" if turn.get("actionKind") == "guiAction" else "native_action"


def infer_action_args(action_type: str, instruction: str, execution_step: dict[str, Any] | None) -> dict[str, Any]:
    args: dict[str, Any] = {}
    if isinstance(instruction, str) and instruction.strip():
        args["instruction"] = instruction.strip()

    target_hint = (execution_step or {}).get("target")
    if isinstance(target_hint, str) and target_hint.strip():
        args["targetHint"] = target_hint.strip()

    if action_type == "type":
        match = re.search(r'(?:输入|input|type)\s*[“"](.+?)[”"]', instruction, re.IGNORECASE)
        if match:
            args["text"] = match.group(1)
    if action_type == "shortcut":
        if "回车" in instruction or " enter" in instruction.lower() or " return" in instruction.lower():
            args["keys"] = ["return"]
        else:
            match = re.search(r"(?:快捷键|shortcut)\s+([A-Za-z0-9+_-]+)", instruction, re.IGNORECASE)
            if match:
                args["keys"] = [token for token in match.group(1).split("+") if token]
    return args


def selector_candidates(turn: dict[str, Any], step_mapping: dict[str, Any] | None) -> tuple[list[dict[str, Any]], str | None]:
    semantic_ref = turn.get("semanticTargetSetRef") or {}
    preferred_locator_type = semantic_ref.get("preferredLocatorType") or (step_mapping or {}).get("preferredLocatorType")
    candidates = semantic_ref.get("semanticTargets") or (step_mapping or {}).get("semanticTargets") or []
    return [candidate for candidate in candidates if isinstance(candidate, dict)], preferred_locator_type


def choose_primary_selector(
    candidates: list[dict[str, Any]],
    preferred_locator_type: str | None,
    app_context: dict[str, Any],
) -> dict[str, Any]:
    if candidates:
        if preferred_locator_type:
            preferred_semantic = [
                candidate
                for candidate in candidates
                if candidate.get("locatorType") == preferred_locator_type and candidate.get("locatorType") != "coordinateFallback"
            ]
            if preferred_semantic:
                return preferred_semantic[0]

        non_coordinate = [candidate for candidate in candidates if candidate.get("locatorType") != "coordinateFallback"]
        if non_coordinate:
            non_coordinate.sort(key=lambda item: float(item.get("confidence") or 0), reverse=True)
            return non_coordinate[0]

        if preferred_locator_type:
            preferred_candidates = [
                candidate for candidate in candidates if candidate.get("locatorType") == preferred_locator_type
            ]
            if preferred_candidates:
                return preferred_candidates[0]
        return candidates[0]

    return {
        "locatorType": "unknown",
        "appBundleId": app_context.get("appBundleId") or "unknown.bundle.id",
        "windowTitlePattern": exact_window_title_pattern(app_context.get("windowTitle")),
        "windowSignature": app_context.get("windowSignature"),
        "source": "migration-context-only",
    }


def dedupe_strings(values: list[Any]) -> list[str]:
    deduped: list[str] = []
    seen: set[str] = set()
    for value in values:
        if not isinstance(value, str):
            continue
        normalized = value.strip()
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        deduped.append(normalized)
    return deduped


def source_frame_ids(turn: dict[str, Any]) -> list[str]:
    observation = turn.get("observationRef") or {}
    return dedupe_strings(
        list(observation.get("screenshotRefs") or [])
        + list(observation.get("axRefs") or [])
        + list(observation.get("ocrRefs") or [])
    )


def load_skill_context(
    turn: dict[str, Any],
    workspace_root: Path,
    cache: dict[Path, dict[str, Any]],
) -> tuple[Path | None, dict[str, Any] | None, dict[str, Any] | None]:
    candidate_paths: list[str] = []

    semantic_ref = turn.get("semanticTargetSetRef") or {}
    if semantic_ref.get("sourcePath"):
        candidate_paths.append(semantic_ref["sourcePath"])

    for source_ref in turn.get("sourceRefs") or []:
        if source_ref.get("artifactKind") == "skillBundle" and source_ref.get("path"):
            candidate_paths.append(source_ref["path"])

    skill_step_id = semantic_ref.get("sourceStepId") or (turn.get("stepReference") or {}).get("skillStepId")

    for raw_path in candidate_paths:
        skill_path = resolve_path(raw_path, workspace_root)
        if skill_path is None or not skill_path.exists():
            continue
        if skill_path not in cache:
            cache[skill_path] = read_json(skill_path)
        payload = cache[skill_path]
        mappings = payload.get("provenance", {}).get("stepMappings") or []
        execution_steps = payload.get("mappedOutput", {}).get("executionPlan", {}).get("steps") or []

        mapping = None
        if skill_step_id:
            mapping = next((item for item in mappings if item.get("skillStepId") == skill_step_id), None)
        if mapping is None:
            knowledge_step_id = (turn.get("stepReference") or {}).get("knowledgeStepId") or turn.get("stepId")
            mapping = next((item for item in mappings if item.get("knowledgeStepId") == knowledge_step_id), None)
        execution_step = None
        if skill_step_id:
            execution_step = next((item for item in execution_steps if item.get("stepId") == skill_step_id), None)
        if execution_step is None and mapping is not None:
            execution_step = next(
                (item for item in execution_steps if item.get("stepId") == mapping.get("skillStepId")),
                None,
            )
        return skill_path, mapping, execution_step

    return None, None, None


def turn_source_event_ids(turn: dict[str, Any], step_mapping: dict[str, Any] | None) -> list[str]:
    explicit = dedupe_strings(
        list((step_mapping or {}).get("sourceEventIds") or [])
        + list((turn.get("stepReference") or {}).get("sourceEventIds") or [])
    )
    if explicit:
        return explicit
    observation = turn.get("observationRef") or {}
    return dedupe_strings(list(observation.get("eventIds") or []))


def has_semantic_candidates(candidates: list[dict[str, Any]]) -> bool:
    return any(candidate.get("locatorType") not in {None, "unknown", "coordinateFallback"} for candidate in candidates)


def is_historical_conversion_candidate(candidates: list[dict[str, Any]], selector: dict[str, Any]) -> bool:
    locator_type = selector.get("locatorType")
    return locator_type in {None, "unknown", "coordinateFallback"} or not has_semantic_candidates(candidates)


def rebuild_targets_from_bundle(
    action_id: str,
    bundle_targets: list[SemanticActionTargetRecord],
    created_at: str,
) -> list[SemanticActionTargetRecord]:
    targets: list[SemanticActionTargetRecord] = []
    for index, target in enumerate(bundle_targets, start=1):
        targets.append(
            SemanticActionTargetRecord(
                target_id=f"{action_id}:target:{index:02d}",
                target_role=target.target_role,
                ordinal=index,
                selector=deep_copy_json(target.selector),
                created_at=created_at,
                context=deep_copy_json(target.context),
                locator_type=target.locator_type,
                confidence=target.confidence,
                is_preferred=target.is_preferred,
            )
        )
    return targets


def rebuild_assertions_from_bundle(
    action_id: str,
    bundle_assertions: list[SemanticActionAssertionRecord],
    created_at: str,
) -> list[SemanticActionAssertionRecord]:
    assertions: list[SemanticActionAssertionRecord] = []
    for index, assertion in enumerate(bundle_assertions):
        assertions.append(
            SemanticActionAssertionRecord(
                assertion_id=f"{action_id}:assertion:{index + 1:02d}",
                assertion_type=assertion.assertion_type,
                assertion=deep_copy_json(assertion.assertion),
                created_at=created_at,
                source=assertion.source,
                is_required=assertion.is_required,
                ordinal=assertion.ordinal,
            )
        )
    return assertions


def recover_historical_semantic_bundle(
    *,
    turn: dict[str, Any],
    step_mapping: dict[str, Any] | None,
    action_type: str,
    workspace_root: Path,
    builder_cache: dict[tuple[Path, Path], dict[str, Any]],
) -> tuple[dict[str, Any] | None, str]:
    observation = turn.get("observationRef") or {}
    raw_event_log_path = resolve_path(observation.get("rawEventLogPath"), workspace_root)
    if raw_event_log_path is None or not raw_event_log_path.exists():
        return None, HISTORICAL_REASON_MISSING_RAW_EVENT_LOG

    task_chunk_path = resolve_path(observation.get("taskChunkPath"), workspace_root)
    if task_chunk_path is None or not task_chunk_path.exists():
        return None, HISTORICAL_REASON_MISSING_TASK_CHUNK

    source_event_ids = turn_source_event_ids(turn, step_mapping)
    if not source_event_ids:
        return None, HISTORICAL_REASON_SOURCE_EVENTS_MISSING

    cache_key = (task_chunk_path.resolve(), raw_event_log_path.resolve())
    if cache_key not in builder_cache:
        task_chunk = read_json(task_chunk_path)
        events = read_jsonl(raw_event_log_path)
        bundles, summary = build_actions_for_task_chunk(
            task_chunk=task_chunk,
            task_chunk_path=task_chunk_path,
            raw_event_log_path=raw_event_log_path,
            events=events,
            workspace_root=workspace_root,
        )
        builder_cache[cache_key] = {
            "bundles": bundles,
            "summary": summary,
        }

    turn_event_set = set(source_event_ids)
    scored_matches: list[tuple[int, int, int, int, int, Any, list[str]]] = []
    for bundle in builder_cache[cache_key]["bundles"]:
        overlap_ids = [event_id for event_id in bundle.action.source_event_ids if event_id in turn_event_set]
        if not overlap_ids:
            continue
        overlap_count = len(overlap_ids)
        exact_match = 1 if overlap_count == len(turn_event_set) else 0
        action_type_match = 1 if bundle.action.action_type == action_type else 0
        semantic_target_count = sum(
            1
            for target in bundle.targets
            if target.locator_type not in {None, "unknown", "coordinateFallback"}
        )
        prefers_auto = 1 if not bundle.action.manual_review_required else 0
        scored_matches.append(
            (
                exact_match,
                action_type_match,
                overlap_count,
                semantic_target_count,
                prefers_auto,
                bundle,
                overlap_ids,
            )
        )

    if not scored_matches:
        return None, HISTORICAL_REASON_NO_MATCH

    scored_matches.sort(
        key=lambda item: (
            item[0],
            item[1],
            item[2],
            item[3],
            item[4],
        ),
        reverse=True,
    )
    matched_bundle = scored_matches[0][5]
    matched_event_ids = scored_matches[0][6]

    recovered_targets = [deep_copy_json(target.selector) for target in matched_bundle.targets]
    if not has_semantic_candidates(recovered_targets):
        return None, HISTORICAL_REASON_COORDINATE_ONLY

    recovered_selector = deep_copy_json(matched_bundle.action.selector)
    recovered_context = deep_copy_json(matched_bundle.action.context)
    reason_code = (
        HISTORICAL_REASON_REQUIRES_MANUAL_REVIEW
        if matched_bundle.action.manual_review_required
        else HISTORICAL_REASON_AUTO_CONVERTED
    )
    return (
        {
            "bundle": matched_bundle,
            "selector": recovered_selector,
            "targets": recovered_targets,
            "context": recovered_context,
            "matchedSourceEventIds": matched_event_ids,
            "rawEventLogPath": repo_relative_or_abs(raw_event_log_path, workspace_root),
            "taskChunkPath": repo_relative_or_abs(task_chunk_path, workspace_root),
            "reasonCode": reason_code,
        },
        reason_code,
    )


def build_assertions(
    action_id: str,
    turn: dict[str, Any],
    selector: dict[str, Any],
    created_at: str,
) -> list[SemanticActionAssertionRecord]:
    assertions: list[SemanticActionAssertionRecord] = []
    app_context = turn.get("appContext") or {}
    app_bundle_id = app_context.get("appBundleId")
    if isinstance(app_bundle_id, str) and app_bundle_id.strip():
        assertions.append(
            SemanticActionAssertionRecord(
                assertion_id=f"{action_id}:assertion:required-frontmost-app",
                assertion_type="requiredFrontmostApp",
                assertion={"appBundleId": app_bundle_id.strip()},
                created_at=created_at,
                source="migration-turn-app-context",
                ordinal=0,
            )
        )

    window_title_pattern = selector.get("windowTitlePattern") or exact_window_title_pattern(app_context.get("windowTitle"))
    if isinstance(window_title_pattern, str) and window_title_pattern.strip():
        assertions.append(
            SemanticActionAssertionRecord(
                assertion_id=f"{action_id}:assertion:window-title",
                assertion_type="windowTitlePattern",
                assertion={"pattern": window_title_pattern.strip()},
                created_at=created_at,
                source="migration-turn-app-context",
                ordinal=1,
            )
        )

    locator_type = selector.get("locatorType")
    if isinstance(locator_type, str) and locator_type.strip():
        assertions.append(
            SemanticActionAssertionRecord(
                assertion_id=f"{action_id}:assertion:selector-resolvable",
                assertion_type="selectorResolvable",
                assertion={
                    "locatorType": locator_type.strip(),
                    "elementRole": selector.get("elementRole"),
                    "elementTitle": selector.get("elementTitle"),
                    "elementIdentifier": selector.get("elementIdentifier"),
                },
                created_at=created_at,
                source="migration-selector",
                ordinal=2,
            )
        )

    return assertions


def build_execution_logs(
    action_id: str,
    turn: dict[str, Any],
    step_mapping: dict[str, Any] | None,
    selector: dict[str, Any],
) -> list[SemanticActionExecutionLogRecord]:
    execution = turn.get("execution")
    if not isinstance(execution, dict):
        return []

    selector_path = [
        value
        for value in ((step_mapping or {}).get("locatorStrategyOrder") or [])
        if isinstance(value, str) and value.strip()
    ]
    if not selector_path:
        selector_path = [selector.get("locatorType")] if selector.get("locatorType") else []

    result = {
        "skillName": execution.get("skillName"),
        "skillDirectoryPath": execution.get("skillDirectoryPath"),
        "planId": execution.get("planId"),
        "planStepId": execution.get("planStepId"),
        "reviewId": execution.get("reviewId"),
        "status": execution.get("status"),
    }

    return [
        SemanticActionExecutionLogRecord(
            execution_log_id=f"{action_id}:execution:01",
            trace_id=execution.get("traceId") or turn.get("traceId"),
            component=execution.get("component"),
            status=str(execution.get("status") or turn.get("status") or "captured"),
            error_code=execution.get("errorCode"),
            selector_hit_path=selector_path,
            result=result,
            duration_ms=duration_millis(turn.get("startedAt"), turn.get("endedAt")),
            execution_log_path=execution.get("executionLogPath"),
            execution_result_path=execution.get("executionResultPath"),
            review_id=execution.get("reviewId"),
            executed_at=str(turn.get("endedAt") or turn.get("startedAt") or execution.get("traceId") or ""),
        )
    ]


def build_action_bundle(
    turn: dict[str, Any],
    workspace_root: Path,
    skill_cache: dict[Path, dict[str, Any]],
    builder_cache: dict[tuple[Path, Path], dict[str, Any]],
) -> tuple[SemanticActionRecord, list[SemanticActionTargetRecord], list[SemanticActionAssertionRecord], list[SemanticActionExecutionLogRecord]] | tuple[None, str]:
    if turn.get("actionKind") != "guiAction":
        return None, "non_gui_turn"

    turn_id = turn.get("turnId")
    session_id = turn.get("sessionId")
    if not isinstance(turn_id, str) or not turn_id.strip():
        return None, "missing_turn_id"
    if not isinstance(session_id, str) or not session_id.strip():
        return None, "missing_session_id"

    skill_path, step_mapping, execution_step = load_skill_context(turn, workspace_root, skill_cache)
    action_type = infer_action_type(turn, execution_step)
    app_context = turn.get("appContext") or {}
    candidates, preferred_locator_type = selector_candidates(turn, step_mapping)
    selector = choose_primary_selector(candidates, preferred_locator_type, app_context)

    selected_locator_type = selector.get("locatorType")
    manual_review_required = (
        selected_locator_type in {None, "coordinateFallback", "unknown"}
        or not has_semantic_candidates(candidates)
        or turn.get("riskLevel") in {"high", "critical"}
    )

    instruction = str((turn.get("stepReference") or {}).get("instruction") or turn.get("actionSummary") or "")
    args = infer_action_args(action_type, instruction, execution_step)
    if step_mapping is not None:
        if step_mapping.get("requiresTeacherConfirmation") is not None:
            args["requiresTeacherConfirmation"] = bool(step_mapping.get("requiresTeacherConfirmation"))
        if step_mapping.get("notes"):
            args["notes"] = step_mapping.get("notes")

    observation = turn.get("observationRef") or {}
    context = {
        "mode": turn.get("mode"),
        "turnKind": turn.get("turnKind"),
        "status": turn.get("status"),
        "learningState": turn.get("learningState"),
        "riskLevel": turn.get("riskLevel"),
        "appContext": app_context,
        "observationRef": {
            "sourceRecordPath": observation.get("sourceRecordPath"),
            "rawEventLogPath": observation.get("rawEventLogPath"),
            "taskChunkPath": observation.get("taskChunkPath"),
            "eventIds": observation.get("eventIds") or [],
            "screenshotRefs": observation.get("screenshotRefs") or [],
            "axRefs": observation.get("axRefs") or [],
            "ocrRefs": observation.get("ocrRefs") or [],
        },
        "sourceRefs": turn.get("sourceRefs") or [],
        "buildDiagnostics": turn.get("buildDiagnostics") or [],
        "review": turn.get("review"),
    }
    historical_conversion: dict[str, Any] = {
        "source": "sem301-coordinate-to-semantic",
        "candidate": False,
        "status": "not_needed",
        "reasonCode": HISTORICAL_REASON_NOT_NEEDED,
    }

    recovered_bundle = None
    if is_historical_conversion_candidate(candidates, selector):
        historical_conversion["candidate"] = True
        recovered, reason_code = recover_historical_semantic_bundle(
            turn=turn,
            step_mapping=step_mapping,
            action_type=action_type,
            workspace_root=workspace_root,
            builder_cache=builder_cache,
        )
        if recovered is not None:
            recovered_bundle = recovered["bundle"]
            historical_conversion.update(
                {
                    "status": "auto_converted"
                    if recovered["reasonCode"] == HISTORICAL_REASON_AUTO_CONVERTED
                    else "manual_review_required",
                    "reasonCode": recovered["reasonCode"],
                    "matchedBuilderActionId": recovered_bundle.action.action_id,
                    "matchedSourceEventIds": recovered["matchedSourceEventIds"],
                    "originalActionType": action_type,
                    "recoveredActionType": recovered_bundle.action.action_type,
                    "recoveredLocatorType": recovered["selector"].get("locatorType"),
                    "recoveredSelectorStrategy": recovered["selector"].get("selectorStrategy"),
                    "rawEventLogPath": recovered["rawEventLogPath"],
                    "taskChunkPath": recovered["taskChunkPath"],
                    "selectorSummary": recovered["context"].get("selectorSummary"),
                    "builderDiagnostics": recovered["context"].get("builderDiagnostics") or recovered_bundle.diagnostics,
                }
            )
            action_type = recovered_bundle.action.action_type
            selector = recovered["selector"]
            candidates = recovered["targets"]
            preferred_locator_type = recovered_bundle.action.preferred_locator_type or selector.get("locatorType")
            args = {
                **args,
                **deep_copy_json(recovered_bundle.action.args),
            }
            manual_review_required = bool(
                recovered_bundle.action.manual_review_required or turn.get("riskLevel") in {"high", "critical"}
            )
        else:
            historical_conversion.update(
                {
                    "status": "manual_review_required",
                    "reasonCode": reason_code,
                }
            )
            manual_review_required = True

    if step_mapping is not None:
        if step_mapping.get("requiresTeacherConfirmation") is not None:
            args["requiresTeacherConfirmation"] = bool(step_mapping.get("requiresTeacherConfirmation"))
        if step_mapping.get("notes"):
            args["notes"] = step_mapping.get("notes")

    context["historicalConversion"] = historical_conversion

    created_at = str(turn.get("startedAt") or turn.get("endedAt") or "")
    updated_at = str(turn.get("endedAt") or turn.get("startedAt") or "")
    action_id = f"semantic-action-{turn_id}"
    primary_selector_json = deep_copy_json(selector)
    source_event_ids = turn_source_event_ids(turn, step_mapping)

    action = SemanticActionRecord(
        action_id=action_id,
        schema_version=SCHEMA_VERSION,
        session_id=session_id,
        task_id=turn.get("taskId"),
        turn_id=turn_id,
        trace_id=turn.get("traceId"),
        step_id=turn.get("stepId"),
        step_index=turn.get("stepIndex"),
        action_type=action_type,
        selector=primary_selector_json,
        args=args,
        context=deep_copy_json(context),
        confidence=float(selector.get("confidence") or 0.0),
        source_event_ids=source_event_ids,
        source_frame_ids=source_frame_ids(turn),
        source_path=repo_relative_or_abs(skill_path, workspace_root) if skill_path else None,
        preferred_locator_type=preferred_locator_type,
        manual_review_required=manual_review_required,
        legacy_coordinate=(step_mapping or {}).get("coordinate")
        or (deep_copy_json(recovered_bundle.action.legacy_coordinate) if recovered_bundle else None),
        created_at=created_at,
        updated_at=updated_at,
    )

    if recovered_bundle is not None:
        targets = rebuild_targets_from_bundle(action_id, recovered_bundle.targets, created_at)
        assertions = rebuild_assertions_from_bundle(action_id, recovered_bundle.assertions, created_at)
    else:
        targets = []
        for index, candidate in enumerate(candidates, start=1):
            target_id = f"{action_id}:target:{index:02d}"
            targets.append(
                SemanticActionTargetRecord(
                    target_id=target_id,
                    target_role="primary"
                    if candidate == selector
                    else ("fallback" if candidate.get("locatorType") == "coordinateFallback" else "candidate"),
                    ordinal=index,
                    locator_type=candidate.get("locatorType"),
                    selector=deep_copy_json(candidate),
                    context={"preferredLocatorType": preferred_locator_type},
                    confidence=float(candidate.get("confidence") or 0.0) if candidate.get("confidence") is not None else None,
                    is_preferred=(candidate == selector),
                    created_at=created_at,
                )
            )
        assertions = build_assertions(action_id, turn, selector, created_at)

    execution_logs = build_execution_logs(action_id, turn, step_mapping, selector)
    return action, targets, assertions, execution_logs


def backfill_actions(
    *,
    turns_root: Path,
    workspace_root: Path,
    repository: SemanticActionRepository,
    session_id: str | None,
    limit: int | None,
) -> dict[str, Any]:
    turn_paths = sorted(turns_root.rglob("*.json"))
    skill_cache: dict[Path, dict[str, Any]] = {}
    builder_cache: dict[tuple[Path, Path], dict[str, Any]] = {}
    scanned_turns = 0
    written_actions = 0
    skipped_counter: Counter[str] = Counter()
    action_type_counter: Counter[str] = Counter()
    manual_review_required_count = 0
    historical_candidate_count = 0
    historical_auto_converted_count = 0
    historical_reason_counter: Counter[str] = Counter()

    for path in turn_paths:
        if limit is not None and scanned_turns >= limit:
            break
        turn = read_json(path)
        if session_id and turn.get("sessionId") != session_id:
            continue
        scanned_turns += 1

        bundle = build_action_bundle(turn, workspace_root, skill_cache, builder_cache)
        if bundle[0] is None:
            skipped_counter[bundle[1]] += 1
            continue

        action, targets, assertions, execution_logs = bundle
        repository.replace_action(
            action,
            targets=targets,
            assertions=assertions,
            execution_logs=execution_logs,
        )
        written_actions += 1
        action_type_counter[action.action_type] += 1
        if action.manual_review_required:
            manual_review_required_count += 1
        historical_conversion = action.context.get("historicalConversion") or {}
        if historical_conversion.get("candidate"):
            historical_candidate_count += 1
            reason_code = historical_conversion.get("reasonCode")
            if isinstance(reason_code, str) and reason_code.strip():
                historical_reason_counter[reason_code.strip()] += 1
            if (
                historical_conversion.get("status") == "auto_converted"
                and not action.manual_review_required
            ):
                historical_auto_converted_count += 1

    return {
        "scannedTurns": scanned_turns,
        "writtenActions": written_actions,
        "skippedTurns": sum(skipped_counter.values()),
        "skipReasons": dict(sorted(skipped_counter.items())),
        "actionTypeCounts": dict(sorted(action_type_counter.items())),
        "manualReviewRequiredCount": manual_review_required_count,
        "historicalCoordinateCandidateCount": historical_candidate_count,
        "historicalAutoConvertedCount": historical_auto_converted_count,
        "historicalAutoConversionRate": (
            historical_auto_converted_count / historical_candidate_count
            if historical_candidate_count
            else 0.0
        ),
        "historicalConversionReasonCounts": dict(sorted(historical_reason_counter.items())),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--db-path",
        type=Path,
        default=Path("data/semantic-actions/semantic-actions.sqlite"),
        help="SQLite database path for semantic actions. Default: data/semantic-actions/semantic-actions.sqlite",
    )
    parser.add_argument(
        "--workspace-root",
        type=Path,
        default=REPO_ROOT,
        help="Workspace root used to resolve repo-relative source paths. Default: repository root.",
    )
    parser.add_argument(
        "--turns-root",
        type=Path,
        default=Path("data/learning/turns"),
        help="InteractionTurn root used for backfill. Default: data/learning/turns",
    )
    parser.add_argument(
        "--direction",
        choices=["up", "down"],
        default="up",
        help="Schema migration direction. Default: up",
    )
    parser.add_argument("--session-id", help="Optional session filter for the backfill import.")
    parser.add_argument("--limit", type=int, help="Optional max number of turns to scan.")
    parser.add_argument(
        "--skip-backfill",
        action="store_true",
        help="Only apply/rollback schema migrations without importing InteractionTurn data.",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Delete existing semantic action rows before backfill.",
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON summary.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    db_path = args.db_path.resolve()
    workspace_root = args.workspace_root.resolve()
    turns_root = resolve_path(args.turns_root.as_posix(), workspace_root) if not args.turns_root.is_absolute() else args.turns_root.resolve()

    migration_manager = SemanticActionMigrationManager(db_path)
    repository = SemanticActionRepository(db_path)

    if args.direction == "down":
        rolled_back = migration_manager.migrate_down()
        result = {
            "dbPath": str(db_path),
            "direction": "down",
            "rolledBackMigrations": rolled_back,
        }
    else:
        applied = migration_manager.migrate_up()
        result = {
            "dbPath": str(db_path),
            "direction": "up",
            "appliedMigrations": applied,
        }
        if not args.skip_backfill:
            if args.clean:
                repository.clear_all()
            result["backfill"] = backfill_actions(
                turns_root=turns_root,
                workspace_root=workspace_root,
                repository=repository,
                session_id=args.session_id,
                limit=args.limit,
            )
            result["storedActionCount"] = repository.count_actions()

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(f"dbPath={result['dbPath']}")
        print(f"direction={result['direction']}")
        if result["direction"] == "up":
            print(f"appliedMigrations={','.join(str(v) for v in result.get('appliedMigrations', [])) or 'none'}")
            if "backfill" in result:
                print(f"writtenActions={result['backfill']['writtenActions']}")
                print(f"storedActionCount={result.get('storedActionCount', 0)}")
        else:
            print(
                f"rolledBackMigrations={','.join(str(v) for v in result.get('rolledBackMigrations', [])) or 'none'}"
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
