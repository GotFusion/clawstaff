#!/usr/bin/env python3
"""Backfill NextStateEvidence artifacts from InteractionTurn-linked sources."""

from __future__ import annotations

import argparse
import json
import shutil
from collections import Counter
from pathlib import Path
from typing import Any

import build_interaction_turns as turn_builder


REPO_ROOT = turn_builder.REPO_ROOT
SCHEMA_VERSION = "openstaff.learning.next-state-evidence.v0"
SOURCE_ORDER = [
    "teacherReview",
    "executionRuntime",
    "replayVerify",
    "driftDetection",
    "chatgptSuggestion",
    "benchmarkResult",
]


def resolve_repo_path(raw_path: str | None) -> Path | None:
    if not raw_path:
        return None
    path = Path(raw_path)
    if path.is_absolute():
        return path
    return (REPO_ROOT / raw_path).resolve()


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


def date_key(timestamp: str) -> str:
    return timestamp[:10] if len(timestamp) >= 10 else "unknown-date"


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = "".join(
        json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n"
        for row in rows
    )
    path.write_text(payload, encoding="utf-8")


def evidence_file_path(output_root: Path, evidence: dict[str, Any]) -> Path:
    return (
        output_root
        / date_key(evidence["timestamp"])
        / evidence["sessionId"]
        / f"{evidence['turnId']}.jsonl"
    )


def default_confidence(source: str) -> float:
    mapping = {
        "teacherReview": 1.0,
        "executionRuntime": 0.9,
        "replayVerify": 0.88,
        "driftDetection": 0.82,
        "chatgptSuggestion": 0.66,
        "benchmarkResult": 0.95,
    }
    return mapping.get(source, 0.5)


def normalized_confidence(value: float) -> float:
    return max(0.0, min(1.0, value))


def contains_token(value: str | None, token: str) -> bool:
    if not value:
        return False
    return token.lower() in value.lower()


def parse_line_reference(raw_value: str | None) -> tuple[str | None, int | None]:
    if not raw_value:
        return None, None
    if "#L" not in raw_value:
        return raw_value, None
    path, _, suffix = raw_value.partition("#L")
    try:
        return path, int(suffix)
    except ValueError:
        return raw_value, None


def make_raw_ref(
    artifact_kind: str,
    path: str,
    *,
    line_number: int | None = None,
    identifier: str | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    return {
        "artifactKind": artifact_kind,
        "path": path,
        "lineNumber": line_number,
        "identifier": identifier,
        "note": note,
    }


def derive_gui_failure_bucket(
    *,
    summary: str,
    decision: str | None = None,
    status: str | None = None,
    error_code: str | None = None,
) -> str | None:
    if decision == "fixLocator":
        return "locator_resolution_failed"
    if decision == "tooDangerous":
        return "risk_blocked"
    if contains_token(error_code, "locator") or contains_token(error_code, "missing-locator"):
        return "locator_resolution_failed"
    if contains_token(error_code, "action-kind") or contains_token(error_code, "action_kind"):
        return "action_kind_mismatch"
    if contains_token(error_code, "blocked") or contains_token(error_code, "risk"):
        return "risk_blocked"
    if contains_token(status, "blocked"):
        return "risk_blocked"
    if contains_token(summary, "locator"):
        return "locator_resolution_failed"
    return None


def derive_role(
    *,
    source: str,
    evaluative_candidate: dict[str, Any] | None,
    directive_candidate: dict[str, Any] | None,
) -> str:
    if evaluative_candidate and directive_candidate:
        return "mixed"
    if directive_candidate:
        return "directive"
    if evaluative_candidate:
        return "evaluative"
    if source == "chatgptSuggestion":
        return "directive"
    return "evaluative"


def derive_severity(
    *,
    summary: str,
    evaluative_candidate: dict[str, Any] | None,
    directive_candidate: dict[str, Any] | None,
    gui_failure_bucket: str | None,
    status: str | None = None,
    error_code: str | None = None,
    decision: str | None = None,
) -> str:
    if decision == "tooDangerous" or gui_failure_bucket == "risk_blocked":
        return "critical"
    if contains_token(status, "blocked") or contains_token(error_code, "blocked"):
        return "critical"

    if evaluative_candidate:
        polarity = evaluative_candidate.get("polarity")
        if polarity == "positive":
            return "info"
        if polarity == "neutral":
            return "warning"
        if polarity == "negative":
            return "warning" if directive_candidate else "error"

    if gui_failure_bucket or contains_token(status, "failed") or contains_token(error_code, "failed"):
        return "error"
    if directive_candidate:
        return "warning"
    if contains_token(summary, "drift detected"):
        return "warning"
    return "info"


def make_evidence(
    *,
    turn: dict[str, Any],
    source: str,
    summary: str,
    raw_refs: list[dict[str, Any]],
    timestamp: str,
    ordinal: int,
    confidence: float | None = None,
    evaluative_candidate: dict[str, Any] | None = None,
    directive_candidate: dict[str, Any] | None = None,
    gui_failure_bucket: str | None = None,
    status: str | None = None,
    error_code: str | None = None,
    decision: str | None = None,
) -> dict[str, Any]:
    gui_failure_bucket = gui_failure_bucket or derive_gui_failure_bucket(
        summary=summary,
        decision=decision,
        status=status,
        error_code=error_code,
    )
    role = derive_role(
        source=source,
        evaluative_candidate=evaluative_candidate,
        directive_candidate=directive_candidate,
    )
    severity = derive_severity(
        summary=summary,
        evaluative_candidate=evaluative_candidate,
        directive_candidate=directive_candidate,
        gui_failure_bucket=gui_failure_bucket,
        status=status,
        error_code=error_code,
        decision=decision,
    )
    timestamp_token = turn_builder.sanitize_token(timestamp)
    evidence_id = (
        f"evidence-{source}-"
        f"{turn_builder.sanitize_token(turn['turnId'])}-"
        f"{ordinal:02d}-"
        f"{timestamp_token}"
    )
    return {
        "schemaVersion": SCHEMA_VERSION,
        "evidenceId": evidence_id,
        "turnId": turn["turnId"],
        "traceId": turn.get("traceId"),
        "sessionId": turn["sessionId"],
        "taskId": turn["taskId"],
        "stepId": turn["stepId"],
        "source": source,
        "summary": summary,
        "rawRefs": raw_refs,
        "timestamp": timestamp,
        "confidence": normalized_confidence(confidence if confidence is not None else default_confidence(source)),
        "severity": severity,
        "role": role,
        "guiFailureBucket": gui_failure_bucket,
        "evaluativeCandidate": evaluative_candidate,
        "directiveCandidate": directive_candidate,
    }


def find_feedback_record(review: dict[str, Any]) -> dict[str, Any] | None:
    raw_ref = review.get("rawRef")
    review_id = review.get("reviewId")
    path = resolve_repo_path(raw_ref)
    if not path or not path.exists() or not review_id:
        return None
    for entry in read_jsonl(path):
        if entry.get("feedbackId") == review_id:
            return entry
    return None


def teacher_review_evidence(turn: dict[str, Any]) -> list[dict[str, Any]]:
    review = turn.get("review")
    if not review or review.get("source") != "teacherReview":
        return []

    feedback = find_feedback_record(review) or {}
    teacher_review = feedback.get("teacherReview") or {}
    decision = review.get("decision") or feedback.get("decision")
    note = teacher_review.get("note") or feedback.get("note") or review.get("note")
    summary = review.get("summary") or teacher_review.get("summary") or decision or "Teacher review recorded."

    evaluative_candidate: dict[str, Any] | None = None
    directive_candidate: dict[str, Any] | None = None
    if decision in {"approved", "rejected", "needsRevision", "tooDangerous", "wrongOrder", "wrongStyle"}:
        evaluative_candidate = {
            "decision": decision,
            "polarity": "positive" if decision == "approved" else "negative",
            "rationale": note,
        }
    if decision in {"fixLocator", "reteach"}:
        directive_candidate = {
            "action": "repair_locator" if decision == "fixLocator" else "reteach_step",
            "hint": note or summary,
            "repairActionType": teacher_review.get("repairActionType") or feedback.get("repairActionType"),
        }

    raw_refs: list[dict[str, Any]] = []
    if review.get("rawRef"):
        raw_refs.append(
            make_raw_ref(
                "teacherFeedback",
                review["rawRef"],
                identifier=review.get("reviewId"),
            )
        )

    log_path, line_number = parse_line_reference(feedback.get("logEntryId"))
    if log_path:
        raw_refs.append(
            make_raw_ref(
                "executionLog",
                turn_builder.repo_relative(resolve_repo_path(log_path)) if resolve_repo_path(log_path) else log_path,
                line_number=line_number,
                identifier=feedback.get("logEntryId"),
            )
        )

    return [
        make_evidence(
            turn=turn,
            source="teacherReview",
            summary=summary,
            raw_refs=raw_refs or [make_raw_ref("teacherFeedback", review.get("rawRef") or "unknown")],
            timestamp=review.get("reviewedAt") or feedback.get("timestamp") or turn["endedAt"],
            ordinal=1,
            evaluative_candidate=evaluative_candidate,
            directive_candidate=directive_candidate,
            decision=decision,
        )
    ]


def execution_runtime_evidence(turn: dict[str, Any]) -> list[dict[str, Any]]:
    execution = turn.get("execution")
    if not execution:
        return []

    status = execution.get("status") or "unknown"
    error_code = execution.get("errorCode")
    summary = f"Execution runtime reported status={status}."
    if error_code:
        summary += f" errorCode={error_code}."

    evaluative_candidate = {
        "decision": status,
        "polarity": "positive" if status.lower() == "succeeded" else "negative",
        "rationale": error_code,
    }
    directive_candidate = None
    gui_failure_bucket = derive_gui_failure_bucket(
        summary=summary,
        status=status,
        error_code=error_code,
    )
    if gui_failure_bucket:
        action_by_bucket = {
            "locator_resolution_failed": "repair_locator",
            "action_kind_mismatch": "rewrite_action_kind",
            "risk_blocked": "require_teacher_confirmation",
        }
        directive_candidate = {
            "action": action_by_bucket[gui_failure_bucket],
            "hint": error_code or summary,
            "repairActionType": None,
        }

    raw_refs: list[dict[str, Any]] = []
    if execution.get("executionLogPath"):
        raw_refs.append(
            make_raw_ref("executionLog", execution["executionLogPath"], identifier=execution.get("traceId"))
        )
    if execution.get("executionResultPath"):
        raw_refs.append(
            make_raw_ref("executionResult", execution["executionResultPath"], identifier=execution.get("traceId"))
        )

    return [
        make_evidence(
            turn=turn,
            source="executionRuntime",
            summary=summary,
            raw_refs=raw_refs or [make_raw_ref("executionTrace", execution.get("traceId") or "unknown")],
            timestamp=turn.get("endedAt") or turn.get("startedAt") or "unknown-date",
            ordinal=2,
            evaluative_candidate=evaluative_candidate,
            directive_candidate=directive_candidate,
            gui_failure_bucket=gui_failure_bucket,
            status=status,
            error_code=error_code,
        )
    ]


def benchmark_result_evidence(turn: dict[str, Any]) -> list[dict[str, Any]]:
    review = turn.get("review")
    if not review or review.get("source") != "benchmarkResult":
        return []

    decision = review.get("decision") or "unknown"
    note = review.get("note")
    evaluative_candidate = {
        "decision": decision,
        "polarity": "positive" if decision == "approved" else "negative",
        "rationale": note,
    }

    raw_refs = [
        make_raw_ref(
            "benchmarkReview",
            review.get("rawRef") or "unknown",
            identifier=review.get("reviewId"),
            note=note,
        )
    ]

    execution = turn.get("execution") or {}
    if execution.get("executionResultPath"):
        raw_refs.append(
            make_raw_ref("executionResult", execution["executionResultPath"], identifier=execution.get("traceId"))
        )

    return [
        make_evidence(
            turn=turn,
            source="benchmarkResult",
            summary=review.get("summary") or "Benchmark review recorded.",
            raw_refs=raw_refs,
            timestamp=review.get("reviewedAt") or turn["endedAt"],
            ordinal=3,
            evaluative_candidate=evaluative_candidate,
            status=execution.get("status"),
            error_code=execution.get("errorCode"),
            decision=decision,
        )
    ]


def build_turn_evidence(turn: dict[str, Any]) -> list[dict[str, Any]]:
    evidence: list[dict[str, Any]] = []
    evidence.extend(teacher_review_evidence(turn))
    evidence.extend(execution_runtime_evidence(turn))
    evidence.extend(benchmark_result_evidence(turn))
    return evidence


def dedupe_evidence(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    deduped: dict[str, dict[str, Any]] = {}
    for record in records:
        deduped[record["evidenceId"]] = record
    return sorted(deduped.values(), key=lambda item: (item["timestamp"], item["evidenceId"]))


def synthetic_examples() -> dict[str, dict[str, Any]]:
    base_turn = {
        "turnId": "turn-assist-taskProgression-task-assist-example-001-step-001",
        "traceId": "trace-learning-assist-task-assist-example-001-step-001",
        "sessionId": "session-assist-example-001",
        "taskId": "task-assist-example-001",
        "stepId": "step-001",
        "endedAt": "2026-03-18T09:40:00Z",
    }

    return {
        "teacherReview-sample.jsonl": make_evidence(
            turn=base_turn,
            source="teacherReview",
            summary="Teacher marked the assist suggestion as wrong order and requested a retry.",
            raw_refs=[
                make_raw_ref(
                    "teacherFeedback",
                    "data/feedback/2026-03-18/session-assist-example-001-task-assist-example-001-teacher-feedback.jsonl",
                    line_number=1,
                    identifier="feedback-assist-001",
                )
            ],
            timestamp="2026-03-18T09:40:30Z",
            ordinal=1,
            evaluative_candidate={
                "decision": "wrongOrder",
                "polarity": "negative",
                "rationale": "The suggestion skipped the teacher's preferred search field focus step.",
            },
        ),
        "replay-verify-sample.jsonl": make_evidence(
            turn=base_turn,
            source="replayVerify",
            summary="Replay verification degraded because the locator fell back to coordinates.",
            raw_refs=[
                make_raw_ref(
                    "replayVerifyReport",
                    "data/replay/2026-03-18/replay-verify-report.json",
                    identifier="replay-step-001",
                )
            ],
            timestamp="2026-03-18T09:41:00Z",
            ordinal=1,
            evaluative_candidate={
                "decision": "degraded",
                "polarity": "negative",
                "rationale": "Replay dry-run only found coordinate fallback.",
            },
            directive_candidate={
                "action": "repair_locator",
                "hint": "Refresh semantic target candidates before the next assist suggestion.",
                "repairActionType": "relocalize",
            },
            gui_failure_bucket="locator_resolution_failed",
            status="degraded",
        ),
        "drift-detection-sample.jsonl": make_evidence(
            turn=base_turn,
            source="driftDetection",
            summary="Drift detector found UI text changed from Save to Submit on the target button.",
            raw_refs=[
                make_raw_ref(
                    "driftReport",
                    "data/skills/drift/2026-03-18/skill-drift-report.json",
                    identifier="drift-step-001",
                )
            ],
            timestamp="2026-03-18T09:42:00Z",
            ordinal=1,
            evaluative_candidate={
                "decision": "driftDetected",
                "polarity": "negative",
                "rationale": "UI text anchor changed.",
            },
            directive_candidate={
                "action": "refresh_skill_locator",
                "hint": "Update the saved title/text anchor from Save to Submit.",
                "repairActionType": "updateSkillLocator",
            },
            gui_failure_bucket="locator_resolution_failed",
        ),
        "chatgpt-suggestion-sample.jsonl": make_evidence(
            turn=base_turn,
            source="chatgptSuggestion",
            summary="ChatGPT suggested replacing the stale click step with a text-anchor-based locator.",
            raw_refs=[
                make_raw_ref(
                    "llmSuggestion",
                    "data/llm/reports/2026-03-18/repair-suggestion.json",
                    identifier="chatgpt-suggestion-001",
                )
            ],
            timestamp="2026-03-18T09:43:00Z",
            ordinal=1,
            confidence=0.72,
            directive_candidate={
                "action": "rewrite_skill_step",
                "hint": "Prefer textAnchor=Submit over coordinateFallback.",
                "repairActionType": "updateSkillLocator",
            },
            gui_failure_bucket="locator_resolution_failed",
        ),
    }


def write_examples(
    evidence_records: list[dict[str, Any]],
    examples_root: Path,
) -> None:
    examples_root.mkdir(parents=True, exist_ok=True)

    real_examples: dict[str, dict[str, Any]] = {}
    for source in ("teacherReview", "executionRuntime", "benchmarkResult"):
        match = next((item for item in evidence_records if item["source"] == source), None)
        if match:
            real_examples[f"{source}-sample.jsonl"] = match

    synthetic = synthetic_examples()
    for file_name, payload in synthetic.items():
        real_examples.setdefault(file_name, payload)

    for file_name, payload in real_examples.items():
        write_jsonl(examples_root / file_name, [payload])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--benchmark-root",
        default=turn_builder.repo_relative(REPO_ROOT / "data/benchmarks/personal-desktop/generated"),
        help="Directory containing generated personal benchmark cases.",
    )
    parser.add_argument(
        "--output-root",
        default=turn_builder.repo_relative(REPO_ROOT / "data/learning/evidence"),
        help="Directory where NextStateEvidence JSONL files will be written.",
    )
    parser.add_argument(
        "--examples-root",
        default=turn_builder.repo_relative(REPO_ROOT / "core/learning/examples/next-state-evidence"),
        help="Directory where example NextStateEvidence JSONL files will be written.",
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

    turns = turn_builder.build_all_turns(benchmark_root)
    evidence_records: list[dict[str, Any]] = []
    turns_with_evidence = 0

    for turn in turns:
        turn_records = dedupe_evidence(build_turn_evidence(turn))
        if turn_records:
            turns_with_evidence += 1
            evidence_records.extend(turn_records)

    evidence_records = dedupe_evidence(evidence_records)

    grouped: dict[Path, list[dict[str, Any]]] = {}
    for evidence in evidence_records:
        file_path = evidence_file_path(output_root, evidence)
        grouped.setdefault(file_path, []).append(evidence)

    for file_path, rows in grouped.items():
        write_jsonl(file_path, rows)

    write_examples(evidence_records, examples_root)

    source_counts = Counter(item["source"] for item in evidence_records)
    summary = {
        "writtenEvidenceCount": len(evidence_records),
        "turnsWithEvidenceCount": turns_with_evidence,
        "sourceCounts": dict(sorted(source_counts.items())),
        "outputRoot": turn_builder.repo_relative(output_root),
        "examplesRoot": turn_builder.repo_relative(examples_root),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
