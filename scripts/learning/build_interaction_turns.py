#!/usr/bin/env python3
"""Backfill InteractionTurn artifacts from benchmark and student review data."""

from __future__ import annotations

import argparse
import copy
import json
import shutil
from collections import Counter
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_VERSION = "openstaff.learning.interaction-turn.v0"
OBSERVATION_NOTE = (
    "Backfilled from raw event sidecar; screenshot/AX/OCR refs stay empty until ObservationBundle lands."
)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    if not path.exists():
        return records
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        records.append(json.loads(line))
    return records


def sanitize_token(raw: str) -> str:
    token = "".join(ch if ch.isalnum() or ch in "-_" else "-" for ch in raw)
    return token or "turn"


def build_turn_id(mode: str, turn_kind: str, task_id: str, step_id: str) -> str:
    return f"turn-{mode}-{turn_kind}-{sanitize_token(task_id)}-{step_id}"


def build_trace_id(mode: str, task_id: str, step_id: str) -> str:
    return f"trace-learning-{mode}-{sanitize_token(task_id)}-{step_id}"


def date_key(timestamp: str) -> str:
    return timestamp[:10] if len(timestamp) >= 10 else "unknown-date"


def repo_relative(path: Path) -> str:
    try:
        return path.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def action_kind_from_step(action_type: str | None) -> str:
    if action_type in {"click", "input", "shortcut"}:
        return "guiAction"
    return "nativeAction"


def risk_level(
    action_kind: str,
    review_decision: str | None,
    preferred_locator_type: str | None,
    error_code: str | None,
    privacy_tags: list[str] | None = None,
) -> str:
    tags = [tag.lower() for tag in (privacy_tags or [])]
    if review_decision == "tooDangerous":
        return "critical"
    if any(token in tag for tag in tags for token in ("excluded", "sensitive", "redacted")):
        return "high"
    if preferred_locator_type == "coordinateFallback" or error_code:
        return "high"
    if action_kind == "nativeAction":
        return "medium"
    return "low"


def learning_state(review: dict[str, Any] | None, privacy_tags: list[str] | None) -> str:
    tags = [tag.lower() for tag in (privacy_tags or [])]
    if any(token in tag for tag in tags for token in ("excluded", "sensitive", "redacted")):
        return "excluded"
    if review:
        return "reviewed"
    return "linked"


def status_from_execution(step_status: str | None, default: str = "captured") -> str:
    if not step_status:
        return default
    lowered = step_status.lower()
    if "block" in lowered:
        return "blocked"
    if "fail" in lowered:
        return "failed"
    if "succeed" in lowered or "complete" in lowered:
        return "succeeded"
    return default


def build_app_context(
    *,
    knowledge: dict[str, Any] | None = None,
    source_record: dict[str, Any] | None = None,
    raw_event: dict[str, Any] | None = None,
    mapped_context: dict[str, Any] | None = None,
) -> dict[str, Any]:
    knowledge_context = (knowledge or {}).get("context", {})
    source_context = (source_record or {}).get("context", {})
    raw_context = (raw_event or {}).get("contextSnapshot", {})
    mapped_context = mapped_context or {}
    return {
        "appName": knowledge_context.get("appName")
        or mapped_context.get("appName")
        or source_context.get("appName")
        or raw_context.get("appName")
        or "Unknown",
        "appBundleId": knowledge_context.get("appBundleId")
        or mapped_context.get("appBundleId")
        or raw_context.get("appBundleId")
        or "unknown.bundle.id",
        "windowTitle": knowledge_context.get("windowTitle")
        or mapped_context.get("windowTitle")
        or source_context.get("windowTitle")
        or raw_context.get("windowTitle"),
        "windowId": knowledge_context.get("windowId") or raw_context.get("windowId"),
        "windowSignature": raw_context.get("windowSignature", {}).get("signature")
        if isinstance(raw_context.get("windowSignature"), dict)
        else None,
    }


def build_observation_ref(
    *,
    app_context: dict[str, Any],
    source_record_path: str | None,
    raw_event_log_path: str | None,
    task_chunk_path: str | None,
    event_ids: list[str],
) -> dict[str, Any]:
    return {
        "sourceRecordPath": source_record_path,
        "rawEventLogPath": raw_event_log_path,
        "taskChunkPath": task_chunk_path,
        "eventIds": event_ids,
        "screenshotRefs": [],
        "axRefs": [],
        "ocrRefs": [],
        "appContext": app_context,
        "note": OBSERVATION_NOTE,
    }


def build_semantic_target_set_ref(
    step_mapping: dict[str, Any] | None,
    skill_json_path: str | None,
) -> dict[str, Any] | None:
    if not step_mapping:
        return None
    semantic_targets = step_mapping.get("semanticTargets") or []
    return {
        "sourcePath": skill_json_path,
        "sourceStepId": step_mapping.get("skillStepId"),
        "preferredLocatorType": step_mapping.get("preferredLocatorType"),
        "candidateCount": len(semantic_targets),
        "semanticTargets": semantic_targets,
    }


def build_source_refs(artifacts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    refs: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str | None]] = set()
    for artifact in artifacts:
        path = artifact.get("path")
        kind = artifact.get("artifactKind")
        identifier = artifact.get("identifier")
        if not path or not kind:
            continue
        key = (kind, path, identifier)
        if key in seen:
            continue
        seen.add(key)
        refs.append(
            {
                "artifactKind": kind,
                "path": path,
                "identifier": identifier,
                "sha256": artifact.get("sha256"),
            }
        )
    return refs


def build_review_link_from_benchmark(review_result: dict[str, Any], review_result_path: str) -> dict[str, Any]:
    notes = review_result.get("notes") or []
    note = "\n".join(notes) if notes else None
    return {
        "reviewId": f"benchmark-review-{review_result['caseId']}",
        "source": "benchmarkResult",
        "decision": review_result["decision"],
        "summary": review_result["summary"],
        "note": note,
        "reviewedAt": review_result["reviewedAt"],
        "rawRef": review_result_path,
    }


def build_execution_link_from_benchmark(
    execution_result: dict[str, Any],
    review: dict[str, Any],
    step_result: dict[str, Any],
    execution_result_path: str,
) -> dict[str, Any]:
    review_payload = execution_result.get("review") or {}
    return {
        "traceId": execution_result["traceId"],
        "component": f"{review_payload.get('component', 'student.openclaw.runner')}.step",
        "skillName": execution_result.get("skillName"),
        "skillDirectoryPath": execution_result.get("skillDirectoryPath"),
        "planId": None,
        "planStepId": None,
        "status": step_result.get("status", execution_result.get("status", "unknown")),
        "errorCode": step_result.get("errorCode") or execution_result.get("errorCode"),
        "executionLogPath": review_payload.get("logFilePath"),
        "executionResultPath": execution_result_path,
        "reviewId": review_payload.get("reviewId"),
    }


def load_case_bundle(case_dir: Path) -> dict[str, Any]:
    case_report = read_json(case_dir / "case-report.json")
    source_record = read_json(case_dir / "source-record.json")
    execution_result = read_json(case_dir / "execution-result.json")
    review_result = read_json(case_dir / "review-result.json")
    skill_path = next(case_dir.glob("benchmark-*/openstaff-skill.json"))
    skill_payload = read_json(skill_path)

    knowledge_path = REPO_ROOT / source_record["sourceArtifacts"]["knowledgeItemPath"]
    task_chunk_path = REPO_ROOT / source_record["sourceArtifacts"]["taskChunkPath"]
    raw_event_log_path = REPO_ROOT / source_record["sourceArtifacts"]["rawEventLogPath"]
    knowledge = read_json(knowledge_path)
    task_chunk = read_json(task_chunk_path)
    raw_events = read_jsonl(raw_event_log_path)
    raw_event_by_id = {event["eventId"]: event for event in raw_events}

    return {
        "caseDir": case_dir,
        "caseReport": case_report,
        "sourceRecord": source_record,
        "sourceRecordPath": repo_relative(case_dir / "source-record.json"),
        "reviewResult": review_result,
        "reviewResultPath": repo_relative(case_dir / "review-result.json"),
        "executionResult": execution_result,
        "executionResultPath": repo_relative(case_dir / "execution-result.json"),
        "skillPayload": skill_payload,
        "skillPath": repo_relative(skill_path),
        "knowledge": knowledge,
        "knowledgePath": repo_relative(knowledge_path),
        "taskChunk": task_chunk,
        "taskChunkPath": repo_relative(task_chunk_path),
        "rawEventLogPath": repo_relative(raw_event_log_path),
        "rawEventById": raw_event_by_id,
    }


def benchmark_turns(case_dir: Path) -> list[dict[str, Any]]:
    bundle = load_case_bundle(case_dir)
    knowledge = bundle["knowledge"]
    execution_result = bundle["executionResult"]
    review_result = bundle["reviewResult"]
    source_record = bundle["sourceRecord"]
    step_mappings = bundle["skillPayload"].get("provenance", {}).get("stepMappings") or []
    mapping_by_knowledge_step = {
        mapping.get("knowledgeStepId") or mapping.get("skillStepId"): mapping for mapping in step_mappings
    }
    mapping_by_skill_step = {mapping.get("skillStepId"): mapping for mapping in step_mappings}
    execution_steps = {step["stepId"]: step for step in execution_result.get("stepResults", [])}
    mapped_context = bundle["skillPayload"].get("mappedOutput", {}).get("context", {})
    review_link = build_review_link_from_benchmark(review_result, bundle["reviewResultPath"])

    artifacts = build_source_refs(
        [
            {
                "artifactKind": "sourceRecord",
                "path": bundle["sourceRecordPath"],
                "identifier": source_record.get("caseId"),
            },
            {
                "artifactKind": "caseReport",
                "path": repo_relative(case_dir / "case-report.json"),
                "identifier": bundle["caseReport"].get("caseId"),
            },
            {
                "artifactKind": "rawEventLog",
                "path": bundle["rawEventLogPath"],
                "identifier": knowledge.get("sessionId"),
                "sha256": source_record.get("sourceArtifacts", {}).get("rawEventLogSha256"),
            },
            {
                "artifactKind": "taskChunk",
                "path": bundle["taskChunkPath"],
                "identifier": knowledge.get("taskId"),
                "sha256": source_record.get("sourceArtifacts", {}).get("taskChunkSha256"),
            },
            {
                "artifactKind": "knowledgeItem",
                "path": bundle["knowledgePath"],
                "identifier": knowledge.get("knowledgeItemId"),
                "sha256": source_record.get("sourceArtifacts", {}).get("knowledgeItemSha256"),
            },
            {
                "artifactKind": "skillBundle",
                "path": bundle["skillPath"],
                "identifier": bundle["skillPayload"].get("skillName"),
            },
            {
                "artifactKind": "executionResult",
                "path": bundle["executionResultPath"],
                "identifier": execution_result.get("traceId"),
            },
            {
                "artifactKind": "benchmarkReview",
                "path": bundle["reviewResultPath"],
                "identifier": review_result.get("caseId"),
            },
        ]
        + [
            {
                "artifactKind": "studentReview",
                "path": path,
            }
            for path in source_record.get("legacyArtifacts", {}).get("studentReviewPaths", [])
        ]
        + [
            {
                "artifactKind": "teacherFeedback",
                "path": path,
            }
            for path in source_record.get("legacyArtifacts", {}).get("teacherFeedbackPaths", [])
        ]
    )

    turns: list[dict[str, Any]] = []
    for index, step in enumerate(knowledge.get("steps", []), start=1):
        event_ids = step.get("sourceEventIds") or []
        raw_events = [bundle["rawEventById"].get(event_id) for event_id in event_ids]
        raw_events = [event for event in raw_events if event]
        first_event = raw_events[0] if raw_events else None
        last_event = raw_events[-1] if raw_events else None
        app_context = build_app_context(
            knowledge=knowledge,
            source_record=source_record,
            raw_event=first_event,
            mapped_context=mapped_context,
        )
        observation_ref = build_observation_ref(
            app_context=app_context,
            source_record_path=bundle["sourceRecordPath"],
            raw_event_log_path=bundle["rawEventLogPath"],
            task_chunk_path=bundle["taskChunkPath"],
            event_ids=event_ids,
        )
        mapping = mapping_by_knowledge_step.get(step.get("stepId"))
        semantic_ref = build_semantic_target_set_ref(mapping, bundle["skillPath"])
        skill_step_id = mapping.get("skillStepId") if mapping else step.get("stepId")
        step_result = execution_steps.get(skill_step_id or "")
        execution_link = (
            build_execution_link_from_benchmark(
                execution_result=execution_result,
                review=review_result,
                step_result=step_result,
                execution_result_path=bundle["executionResultPath"],
            )
            if step_result
            else None
        )
        action_kind = action_kind_from_step(step_result.get("actionType") if step_result else None)
        turns.append(
            {
                "schemaVersion": SCHEMA_VERSION,
                "turnId": build_turn_id("teaching", "taskProgression", knowledge["taskId"], step["stepId"]),
                "traceId": build_trace_id("teaching", knowledge["taskId"], step["stepId"]),
                "sessionId": knowledge["sessionId"],
                "taskId": knowledge["taskId"],
                "stepId": step["stepId"],
                "mode": "teaching",
                "turnKind": "taskProgression",
                "stepIndex": index,
                "intentSummary": knowledge["goal"],
                "actionSummary": step["instruction"],
                "actionKind": action_kind,
                "status": "captured",
                "learningState": learning_state(review_link, []),
                "privacyTags": [],
                "riskLevel": risk_level(
                    action_kind=action_kind,
                    review_decision=review_link.get("decision"),
                    preferred_locator_type=(semantic_ref or {}).get("preferredLocatorType"),
                    error_code=(execution_link or {}).get("errorCode"),
                ),
                "appContext": app_context,
                "observationRef": observation_ref,
                "semanticTargetSetRef": semantic_ref,
                "stepReference": {
                    "stepId": step["stepId"],
                    "stepIndex": index,
                    "instruction": step["instruction"],
                    "knowledgeItemId": knowledge["knowledgeItemId"],
                    "knowledgeStepId": step["stepId"],
                    "skillStepId": skill_step_id,
                    "planStepId": None,
                    "sourceEventIds": event_ids,
                },
                "execution": execution_link,
                "review": review_link,
                "sourceRefs": artifacts,
                "startedAt": (first_event or {}).get("timestamp", knowledge["source"]["startTimestamp"]),
                "endedAt": (last_event or {}).get("timestamp", knowledge["source"]["endTimestamp"]),
            }
        )

    for index, step_result in enumerate(execution_result.get("stepResults", []), start=1):
        mapping = mapping_by_skill_step.get(step_result["stepId"])
        knowledge_step_id = (mapping or {}).get("knowledgeStepId") or step_result["stepId"]
        event_ids = (mapping or {}).get("sourceEventIds") or []
        raw_events = [bundle["rawEventById"].get(event_id) for event_id in event_ids]
        raw_events = [event for event in raw_events if event]
        app_context = build_app_context(
            knowledge=knowledge,
            source_record=source_record,
            raw_event=raw_events[0] if raw_events else None,
            mapped_context=mapped_context,
        )
        observation_ref = build_observation_ref(
            app_context=app_context,
            source_record_path=bundle["sourceRecordPath"],
            raw_event_log_path=bundle["rawEventLogPath"],
            task_chunk_path=bundle["taskChunkPath"],
            event_ids=event_ids,
        )
        semantic_ref = build_semantic_target_set_ref(mapping, bundle["skillPath"])
        action_kind = action_kind_from_step(step_result.get("actionType"))
        turns.append(
            {
                "schemaVersion": SCHEMA_VERSION,
                "turnId": build_turn_id("student", "skillExecution", knowledge["taskId"], knowledge_step_id),
                "traceId": execution_result["traceId"],
                "sessionId": execution_result["sessionId"],
                "taskId": execution_result["taskId"],
                "stepId": knowledge_step_id,
                "mode": "student",
                "turnKind": "skillExecution",
                "stepIndex": index,
                "intentSummary": bundle["skillPayload"].get("mappedOutput", {}).get("objective", knowledge["goal"]),
                "actionSummary": (mapping or {}).get("instruction") or step_result.get("output", ""),
                "actionKind": action_kind,
                "status": status_from_execution(step_result.get("status"), default="captured"),
                "learningState": learning_state(review_link, []),
                "privacyTags": [],
                "riskLevel": risk_level(
                    action_kind=action_kind,
                    review_decision=review_link.get("decision"),
                    preferred_locator_type=(semantic_ref or {}).get("preferredLocatorType"),
                    error_code=step_result.get("errorCode"),
                ),
                "appContext": app_context,
                "observationRef": observation_ref,
                "semanticTargetSetRef": semantic_ref,
                "stepReference": {
                    "stepId": knowledge_step_id,
                    "stepIndex": index,
                    "instruction": (mapping or {}).get("instruction") or step_result.get("output", ""),
                    "knowledgeItemId": knowledge["knowledgeItemId"],
                    "knowledgeStepId": knowledge_step_id,
                    "skillStepId": step_result["stepId"],
                    "planStepId": None,
                    "sourceEventIds": event_ids,
                },
                "execution": build_execution_link_from_benchmark(
                    execution_result=execution_result,
                    review=review_result,
                    step_result=step_result,
                    execution_result_path=bundle["executionResultPath"],
                ),
                "review": review_link,
                "sourceRefs": artifacts,
                "startedAt": step_result.get("startedAt", execution_result["startedAt"]),
                "endedAt": step_result.get("finishedAt", execution_result["finishedAt"]),
            }
        )

    return turns


def build_knowledge_indexes() -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
    knowledge_by_task: dict[str, dict[str, Any]] = {}
    task_chunk_by_task: dict[str, dict[str, Any]] = {}
    raw_events_by_session: dict[str, dict[str, Any]] = {}

    for path in (REPO_ROOT / "data/knowledge").glob("*/*.json"):
        payload = read_json(path)
        knowledge_by_task[payload["taskId"]] = {
            "path": repo_relative(path),
            "payload": payload,
        }

    for path in (REPO_ROOT / "data/task-chunks").glob("*/*.json"):
        payload = read_json(path)
        task_chunk_by_task[payload["taskId"]] = {
            "path": repo_relative(path),
            "payload": payload,
        }

    for path in (REPO_ROOT / "data/raw-events").glob("*/*.jsonl"):
        events = read_jsonl(path)
        if not events:
            continue
        raw_events_by_session[events[0]["sessionId"]] = {
            "path": repo_relative(path),
            "events": events,
            "byEventId": {event["eventId"]: event for event in events},
        }

    return knowledge_by_task, task_chunk_by_task, raw_events_by_session


def build_benchmark_skill_index() -> dict[str, dict[str, Any]]:
    skill_index: dict[str, dict[str, Any]] = {}
    for path in (REPO_ROOT / "data/benchmarks/personal-desktop/generated").glob("*/benchmark-*/openstaff-skill.json"):
        payload = read_json(path)
        mappings = payload.get("provenance", {}).get("stepMappings") or []
        skill_index[payload["taskId"]] = {
            "path": repo_relative(path),
            "payload": payload,
            "mappingsByKnowledgeStep": {
                mapping.get("knowledgeStepId") or mapping.get("skillStepId"): mapping for mapping in mappings
            },
        }
    return skill_index


def load_student_logs() -> tuple[dict[str, str], dict[str, dict[str, Any]], dict[str, list[dict[str, Any]]]]:
    log_path_by_session: dict[str, str] = {}
    entries_by_log_ref: dict[str, dict[str, Any]] = {}
    entries_by_session: dict[str, list[dict[str, Any]]] = {}
    for path in (REPO_ROOT / "data/logs").glob("*/*-student.log"):
        entries: list[dict[str, Any]] = []
        for line_no, entry in enumerate(read_jsonl(path), start=1):
            entry_copy = dict(entry)
            log_ref = f"{path.resolve().as_posix()}#L{line_no}"
            entry_copy["_logRef"] = log_ref
            entries.append(entry_copy)
            entries_by_log_ref[log_ref] = entry_copy
        if not entries:
            continue
        session_id = entries[0]["sessionId"]
        log_path_by_session[session_id] = repo_relative(path)
        entries_by_session[session_id] = entries
    return log_path_by_session, entries_by_log_ref, entries_by_session


def load_feedback_by_log_ref() -> tuple[dict[str, dict[str, Any]], dict[str, str]]:
    feedback_by_log_ref: dict[str, dict[str, Any]] = {}
    feedback_path_by_log_ref: dict[str, str] = {}
    for path in (REPO_ROOT / "data/feedback").glob("*/*.jsonl"):
        for entry in read_jsonl(path):
            log_ref = entry.get("logEntryId")
            if not log_ref:
                continue
            previous = feedback_by_log_ref.get(log_ref)
            if previous and previous.get("timestamp", "") >= entry.get("timestamp", ""):
                continue
            feedback_by_log_ref[log_ref] = entry
            feedback_path_by_log_ref[log_ref] = repo_relative(path)
    return feedback_by_log_ref, feedback_path_by_log_ref


def find_matching_feedback(
    *,
    session_entries: list[dict[str, Any]],
    feedback_by_log_ref: dict[str, dict[str, Any]],
    plan_step_id: str,
    total_steps: int,
) -> tuple[dict[str, Any] | None, str | None]:
    candidates: list[tuple[str, dict[str, Any]]] = []
    for entry in session_entries:
        if entry.get("planStepId") == plan_step_id:
            feedback = feedback_by_log_ref.get(entry["_logRef"])
            if feedback:
                candidates.append((entry["_logRef"], feedback))

    if not candidates and total_steps == 1:
        for entry in session_entries:
            if entry.get("status") == "STATUS_ORC_STUDENT_REVIEW_GENERATED":
                feedback = feedback_by_log_ref.get(entry["_logRef"])
                if feedback:
                    candidates.append((entry["_logRef"], feedback))

    if not candidates:
        return None, None

    candidates.sort(key=lambda item: item[1].get("timestamp", ""))
    return candidates[-1][1], candidates[-1][0]


def build_review_link_from_feedback(feedback: dict[str, Any], raw_ref: str) -> dict[str, Any]:
    summary = feedback.get("teacherReview", {}).get("summary") or feedback.get("logMessage") or feedback.get("decision", "")
    note = feedback.get("teacherReview", {}).get("note") or feedback.get("note")
    return {
        "reviewId": feedback["feedbackId"],
        "source": "teacherReview",
        "decision": feedback.get("decision", ""),
        "summary": summary,
        "note": note,
        "reviewedAt": feedback["timestamp"],
        "rawRef": raw_ref,
    }


def live_student_turns() -> list[dict[str, Any]]:
    knowledge_by_task, task_chunk_by_task, raw_events_by_session = build_knowledge_indexes()
    benchmark_skill_index = build_benchmark_skill_index()
    log_path_by_session, feedback_log_index, log_entries_by_session = load_student_logs()
    feedback_by_log_ref, feedback_path_by_log_ref = load_feedback_by_log_ref()

    turns: list[dict[str, Any]] = []
    for report_path in (REPO_ROOT / "data/reports").glob("*/*.json"):
        report = read_json(report_path)
        knowledge_info = knowledge_by_task.get(report["taskId"])
        if not knowledge_info:
            continue
        knowledge = knowledge_info["payload"]
        task_chunk_info = task_chunk_by_task.get(report["taskId"])
        raw_event_info = raw_events_by_session.get(knowledge["sessionId"], {})
        raw_event_by_id = raw_event_info.get("byEventId", {})
        log_entries = log_entries_by_session.get(report["sessionId"], [])
        plan_steps = {step["planStepId"]: step for step in report.get("plan", {}).get("steps", [])}
        knowledge_steps = {step["stepId"]: step for step in knowledge.get("steps", [])}
        log_path = log_path_by_session.get(report["sessionId"])
        skill_info = benchmark_skill_index.get(report["taskId"])

        for index, step_result in enumerate(report.get("stepResults", []), start=1):
            plan_step = plan_steps.get(step_result["planStepId"], {})
            knowledge_step_id = plan_step.get("sourceStepId") or step_result["planStepId"]
            knowledge_step = knowledge_steps.get(knowledge_step_id, {})
            event_ids = knowledge_step.get("sourceEventIds") or []
            step_mapping = (skill_info or {}).get("mappingsByKnowledgeStep", {}).get(knowledge_step_id)
            raw_events = [raw_event_by_id.get(event_id) for event_id in event_ids]
            raw_events = [event for event in raw_events if event]
            app_context = build_app_context(
                knowledge=knowledge,
                raw_event=raw_events[0] if raw_events else None,
            )
            feedback, feedback_raw_ref = find_matching_feedback(
                session_entries=log_entries,
                feedback_by_log_ref=feedback_by_log_ref,
                plan_step_id=step_result["planStepId"],
                total_steps=len(report.get("stepResults", [])),
            )
            review_link = (
                build_review_link_from_feedback(feedback, feedback_raw_ref) if feedback and feedback_raw_ref else None
            )
            source_refs = build_source_refs(
                [
                    {
                        "artifactKind": "studentReview",
                        "path": repo_relative(report_path),
                        "identifier": report.get("reportId"),
                    },
                    {
                        "artifactKind": "studentLog",
                        "path": log_path,
                        "identifier": report.get("traceId"),
                    },
                    {
                        "artifactKind": "knowledgeItem",
                        "path": knowledge_info["path"],
                        "identifier": knowledge.get("knowledgeItemId"),
                    },
                    {
                        "artifactKind": "skillBundle",
                        "path": (skill_info or {}).get("path"),
                        "identifier": ((skill_info or {}).get("payload") or {}).get("skillName"),
                    },
                    {
                        "artifactKind": "taskChunk",
                        "path": (task_chunk_info or {}).get("path"),
                        "identifier": report.get("taskId"),
                    },
                    {
                        "artifactKind": "rawEventLog",
                        "path": raw_event_info.get("path"),
                        "identifier": knowledge.get("sessionId"),
                    },
                    {
                        "artifactKind": "teacherFeedback",
                        "path": feedback_path_by_log_ref.get(feedback_raw_ref),
                        "identifier": (feedback or {}).get("feedbackId"),
                    },
                ]
            )
            action_kind = action_kind_from_step("click")
            semantic_ref = build_semantic_target_set_ref(step_mapping, (skill_info or {}).get("path"))
            execution_link = {
                "traceId": report["traceId"],
                "component": "student.loop",
                "skillName": ((skill_info or {}).get("payload") or {}).get("skillName"),
                "skillDirectoryPath": str(Path((skill_info or {}).get("path", "")).parent.as_posix())
                if (skill_info or {}).get("path")
                else None,
                "planId": report.get("plan", {}).get("planId"),
                "planStepId": step_result["planStepId"],
                "status": step_result.get("status", report.get("finalStatus", "")),
                "errorCode": step_result.get("errorCode"),
                "executionLogPath": log_path,
                "executionResultPath": repo_relative(report_path),
                "reviewId": report.get("reportId"),
            }
            turns.append(
                {
                    "schemaVersion": SCHEMA_VERSION,
                    "turnId": build_turn_id("student", "skillExecution", report["taskId"], knowledge_step_id),
                    "traceId": report["traceId"],
                    "sessionId": report["sessionId"],
                    "taskId": report["taskId"],
                    "stepId": knowledge_step_id,
                    "mode": "student",
                    "turnKind": "skillExecution",
                    "stepIndex": index,
                    "intentSummary": report["goal"],
                    "actionSummary": plan_step.get("instruction") or step_result.get("output", ""),
                    "actionKind": action_kind,
                    "status": status_from_execution(step_result.get("status"), default="captured"),
                    "learningState": learning_state(review_link, []),
                    "privacyTags": [],
                    "riskLevel": risk_level(
                        action_kind=action_kind,
                        review_decision=(review_link or {}).get("decision"),
                        preferred_locator_type=(semantic_ref or {}).get("preferredLocatorType"),
                        error_code=step_result.get("errorCode"),
                    ),
                    "appContext": app_context,
                    "observationRef": build_observation_ref(
                        app_context=app_context,
                        source_record_path=None,
                        raw_event_log_path=raw_event_info.get("path"),
                        task_chunk_path=(task_chunk_info or {}).get("path"),
                        event_ids=event_ids,
                    ),
                    "semanticTargetSetRef": semantic_ref,
                    "stepReference": {
                        "stepId": knowledge_step_id,
                        "stepIndex": index,
                        "instruction": plan_step.get("instruction") or step_result.get("output", ""),
                        "knowledgeItemId": plan_step.get("sourceKnowledgeItemId") or knowledge.get("knowledgeItemId"),
                        "knowledgeStepId": knowledge_step_id,
                        "skillStepId": (step_mapping or {}).get("skillStepId"),
                        "planStepId": step_result["planStepId"],
                        "sourceEventIds": event_ids,
                    },
                    "execution": execution_link,
                    "review": review_link,
                    "sourceRefs": source_refs,
                    "startedAt": step_result.get("startedAt", report["startedAt"]),
                    "endedAt": step_result.get("finishedAt", report["finishedAt"]),
                }
            )
    return turns


def assist_example_turn() -> dict[str, Any]:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "turnId": "turn-assist-taskProgression-task-assist-example-001-step-001",
        "traceId": "trace-learning-assist-task-assist-example-001-step-001",
        "sessionId": "session-assist-example-20260318-090000",
        "taskId": "task-assist-example-001",
        "stepId": "step-001",
        "mode": "assist",
        "turnKind": "taskProgression",
        "stepIndex": 1,
        "intentSummary": "在 Safari 中继续处理 Pull Request，系统预测老师下一步会点击 Merge。",
        "actionSummary": "辅助模式已给出下一步点击建议，并在老师确认后执行。",
        "actionKind": "guiAction",
        "status": "succeeded",
        "learningState": "reviewed",
        "privacyTags": [],
        "riskLevel": "low",
        "appContext": {
            "appName": "Safari",
            "appBundleId": "com.apple.Safari",
            "windowTitle": "OpenStaff - Pull Requests",
            "windowId": "assist-window-001",
            "windowSignature": None,
        },
        "observationRef": {
            "sourceRecordPath": None,
            "rawEventLogPath": None,
            "taskChunkPath": None,
            "eventIds": ["evt-assist-example-001"],
            "screenshotRefs": [],
            "axRefs": [],
            "ocrRefs": [],
            "appContext": {
                "appName": "Safari",
                "appBundleId": "com.apple.Safari",
                "windowTitle": "OpenStaff - Pull Requests",
                "windowId": "assist-window-001",
                "windowSignature": None,
            },
            "note": "Synthetic example for assist mode until real assist history is frozen into the repository.",
        },
        "semanticTargetSetRef": {
            "sourcePath": None,
            "sourceStepId": "step-001",
            "preferredLocatorType": "roleAndTitle",
            "candidateCount": 1,
            "semanticTargets": [
                {
                    "locatorType": "roleAndTitle",
                    "appBundleId": "com.apple.Safari",
                    "windowTitlePattern": "^OpenStaff\\ -\\ Pull\\ Requests$",
                    "windowSignature": None,
                    "elementRole": "AXButton",
                    "elementTitle": "Merge",
                    "elementIdentifier": "merge",
                    "axPath": None,
                    "textAnchor": None,
                    "imageAnchor": None,
                    "boundingRect": {
                        "x": 1120,
                        "y": 428,
                        "width": 88,
                        "height": 32,
                        "coordinateSpace": "screen"
                    },
                    "confidence": 0.92,
                    "source": "capture"
                }
            ]
        },
        "stepReference": {
            "stepId": "step-001",
            "stepIndex": 1,
            "instruction": "点击 Merge 按钮。",
            "knowledgeItemId": "ki-assist-example-001",
            "knowledgeStepId": "step-001",
            "skillStepId": None,
            "planStepId": None,
            "sourceEventIds": ["evt-assist-example-001"]
        },
        "execution": {
            "traceId": "trace-assist-loop-example-001",
            "component": "assist.loop",
            "skillName": None,
            "skillDirectoryPath": None,
            "planId": None,
            "planStepId": None,
            "status": "STATUS_EXE_ASSIST_EXECUTION_COMPLETED",
            "errorCode": None,
            "executionLogPath": None,
            "executionResultPath": None,
            "reviewId": "assist-feedback-example-001"
        },
        "review": {
            "reviewId": "assist-feedback-example-001",
            "source": "example",
            "decision": "approved",
            "summary": "老师接受了辅助模式建议并确认执行结果符合预期。",
            "note": None,
            "reviewedAt": "2026-03-18T09:00:08+08:00",
            "rawRef": "core/learning/examples/interaction-turns/assist-suggestion-sample.json"
        },
        "sourceRefs": [
            {
                "artifactKind": "exampleFixture",
                "path": "core/learning/examples/interaction-turns/assist-suggestion-sample.json",
                "identifier": "assist-example-001",
                "sha256": None
            }
        ],
        "startedAt": "2026-03-18T09:00:01+08:00",
        "endedAt": "2026-03-18T09:00:07+08:00"
    }


def dedupe_turns(turns: list[dict[str, Any]]) -> list[dict[str, Any]]:
    deduped: dict[tuple[str, str, str], dict[str, Any]] = {}
    for turn in turns:
        key = (turn["mode"], turn["sessionId"], turn["turnId"])
        deduped[key] = turn
    return sorted(
        deduped.values(),
        key=lambda item: (item["mode"], item["sessionId"], item["taskId"], item["stepIndex"]),
    )


def write_turns(turns: list[dict[str, Any]], output_root: Path) -> None:
    for turn in turns:
        file_path = output_root / date_key(turn["startedAt"]) / turn["sessionId"] / f"{turn['turnId']}.json"
        write_json(file_path, turn)


def write_examples(turns: list[dict[str, Any]], examples_root: Path) -> None:
    examples_root.mkdir(parents=True, exist_ok=True)
    teaching = next(turn for turn in turns if turn["mode"] == "teaching")
    student = None
    for turn in turns:
        if turn["mode"] != "student":
            continue
        if any(ref.get("artifactKind") == "benchmarkReview" for ref in turn.get("sourceRefs", [])):
            student = turn
            break
    if student is None:
        student = next(turn for turn in turns if turn["mode"] == "student")
    write_json(examples_root / "teaching-benchmark-step.json", teaching)
    write_json(examples_root / "student-benchmark-step.json", student)
    write_json(examples_root / "assist-suggestion-sample.json", assist_example_turn())


def build_all_turns(benchmark_root: Path) -> list[dict[str, Any]]:
    turns: list[dict[str, Any]] = []
    for case_dir in sorted(benchmark_root.iterdir()):
        if case_dir.is_dir():
            turns.extend(benchmark_turns(case_dir))
    turns.extend(live_student_turns())
    return dedupe_turns(turns)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--benchmark-root",
        default=repo_relative(REPO_ROOT / "data/benchmarks/personal-desktop/generated"),
        help="Directory containing generated personal benchmark cases.",
    )
    parser.add_argument(
        "--output-root",
        default=repo_relative(REPO_ROOT / "data/learning/turns"),
        help="Directory where InteractionTurn JSON files will be written.",
    )
    parser.add_argument(
        "--examples-root",
        default=repo_relative(REPO_ROOT / "core/learning/examples/interaction-turns"),
        help="Directory where example InteractionTurn JSON files will be written.",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Remove existing output/examples directory content before writing.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    benchmark_root = (REPO_ROOT / args.benchmark_root).resolve()
    output_root = (REPO_ROOT / args.output_root).resolve()
    examples_root = (REPO_ROOT / args.examples_root).resolve()

    if args.clean:
        for path in (output_root, examples_root):
            if path.exists():
                shutil.rmtree(path)

    turns = build_all_turns(benchmark_root)
    write_turns(turns, output_root)
    write_examples(turns, examples_root)

    mode_counter = Counter(turn["mode"] for turn in turns)
    summary = {
        "writtenTurnCount": len(turns),
        "modeCounts": dict(sorted(mode_counter.items())),
        "outputRoot": repo_relative(output_root),
        "examplesRoot": repo_relative(examples_root),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
