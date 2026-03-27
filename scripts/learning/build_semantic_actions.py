#!/usr/bin/env python3
"""Build SEM-101 semantic actions from task chunks and raw event logs."""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import json
from pathlib import Path

from semantic_action_builder import build_actions_for_task_chunk, read_json, read_jsonl
from semantic_action_store import (
    SemanticActionMigrationManager,
    SemanticActionRepository,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB_PATH = REPO_ROOT / "data/semantic-actions/semantic-actions.sqlite"
DEFAULT_TASK_CHUNKS_ROOT = REPO_ROOT / "data/task-chunks"
DEFAULT_RAW_EVENTS_ROOT = REPO_ROOT / "data/raw-events"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build semantic actions from raw event streams.")
    parser.add_argument(
        "--workspace-root",
        type=Path,
        default=REPO_ROOT,
        help=f"Workspace root used for relative path materialization (default: {REPO_ROOT}).",
    )
    parser.add_argument(
        "--db-path",
        type=Path,
        default=DEFAULT_DB_PATH,
        help=f"SQLite output path (default: {DEFAULT_DB_PATH}).",
    )
    parser.add_argument(
        "--task-chunks-root",
        type=Path,
        default=DEFAULT_TASK_CHUNKS_ROOT,
        help=f"Task chunk root (default: {DEFAULT_TASK_CHUNKS_ROOT}).",
    )
    parser.add_argument(
        "--raw-events-root",
        type=Path,
        default=DEFAULT_RAW_EVENTS_ROOT,
        help=f"Raw event log root (default: {DEFAULT_RAW_EVENTS_ROOT}).",
    )
    parser.add_argument("--session-id", help="Optional session filter.")
    parser.add_argument("--task-id", help="Optional task filter.")
    parser.add_argument("--limit", type=int, help="Optional max task chunk count.")
    parser.add_argument("--clean", action="store_true", help="Clear existing semantic action rows before writing.")
    parser.add_argument("--json", action="store_true", help="Print summary as JSON.")
    return parser.parse_args()


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def load_raw_event_index(raw_events_root: Path) -> dict[str, Path]:
    return {path.stem: path for path in raw_events_root.rglob("*.jsonl")}


def resolve_chunk_events(
    *,
    task_chunk: dict,
    raw_event_log_path: Path,
) -> tuple[list[dict], int]:
    event_lookup = {}
    for event in read_jsonl(raw_event_log_path):
        event_id = event.get("eventId")
        if isinstance(event_id, str) and event_id.strip():
            event_lookup[event_id] = event

    events: list[dict] = []
    missing = 0
    for event_id in task_chunk.get("eventIds") or []:
        event = event_lookup.get(event_id)
        if event is None:
            missing += 1
            continue
        events.append(event)
    return events, missing


def main() -> int:
    args = parse_args()
    workspace_root = args.workspace_root.resolve()
    task_chunks_root = args.task_chunks_root.resolve()
    raw_events_root = args.raw_events_root.resolve()
    db_path = args.db_path.resolve()

    manager = SemanticActionMigrationManager(db_path)
    repository = SemanticActionRepository(db_path)
    migrated_versions = manager.migrate_up()
    if args.clean:
        repository.clear_all()

    raw_event_index = load_raw_event_index(raw_events_root)
    chunk_paths = sorted(task_chunks_root.rglob("*.json"))
    action_type_counts: Counter[str] = Counter()
    skipped_chunk_counts: Counter[str] = Counter()
    manual_review_required_count = 0
    missing_event_count = 0
    total_event_count = 0
    semanticized_event_count = 0
    conflict_diagnostic_count = 0
    written_actions = 0
    processed_chunk_count = 0

    for chunk_path in chunk_paths:
        if args.limit is not None and processed_chunk_count >= args.limit:
            break

        task_chunk = read_json(chunk_path)
        if args.session_id and task_chunk.get("sessionId") != args.session_id:
            continue
        if args.task_id and task_chunk.get("taskId") != args.task_id:
            continue

        processed_chunk_count += 1
        session_id = task_chunk.get("sessionId")
        if not isinstance(session_id, str) or not session_id.strip():
            skipped_chunk_counts["missing_session_id"] += 1
            continue

        raw_event_log_path = raw_event_index.get(session_id)
        if raw_event_log_path is None:
            skipped_chunk_counts["missing_raw_event_log"] += 1
            continue

        events, missing = resolve_chunk_events(task_chunk=task_chunk, raw_event_log_path=raw_event_log_path)
        missing_event_count += missing
        if not events:
            skipped_chunk_counts["empty_event_window"] += 1
            continue

        bundles, summary = build_actions_for_task_chunk(
            task_chunk=task_chunk,
            task_chunk_path=chunk_path,
            raw_event_log_path=raw_event_log_path,
            events=events,
            workspace_root=workspace_root,
        )
        if not bundles:
            skipped_chunk_counts["no_semantic_actions_built"] += 1
            continue

        for bundle in bundles:
            repository.replace_action(
                bundle.action,
                targets=bundle.targets,
                assertions=bundle.assertions,
                execution_logs=bundle.execution_logs,
            )
            action_type_counts[bundle.action.action_type] += 1
            written_actions += 1
            if bundle.action.manual_review_required:
                manual_review_required_count += 1

        total_event_count += summary["inputEventCount"]
        semanticized_event_count += summary["semanticizedEventCount"]
        conflict_diagnostic_count += summary["diagnosticCount"]

    semanticized_ratio = (semanticized_event_count / total_event_count) if total_event_count else 0.0
    result = {
        "schemaVersion": "openstaff.semantic-action-builder-report.v0",
        "generatedAt": utc_now_iso(),
        "workspaceRoot": str(workspace_root),
        "dbPath": str(db_path),
        "migratedVersions": migrated_versions,
        "processedChunkCount": processed_chunk_count,
        "writtenActions": written_actions,
        "storedActionCount": repository.count_actions(),
        "actionTypeCounts": dict(action_type_counts),
        "manualReviewRequiredCount": manual_review_required_count,
        "totalEventCount": total_event_count,
        "semanticizedEventCount": semanticized_event_count,
        "semanticizedEventRatio": semanticized_ratio,
        "missingEventCount": missing_event_count,
        "conflictDiagnosticCount": conflict_diagnostic_count,
        "skippedChunkCounts": dict(skipped_chunk_counts),
    }

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(
            "built semantic actions: "
            f"chunks={processed_chunk_count} actions={written_actions} "
            f"semanticized={semanticized_event_count}/{total_event_count} "
            f"ratio={semanticized_ratio:.3f}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
