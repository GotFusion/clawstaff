#!/usr/bin/env python3
"""SQLite-backed semantic action store and migration helpers."""

from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = "openstaff.semantic-action.v0"
MIGRATIONS_DIR = Path(__file__).resolve().parent / "migrations" / "semantic_actions"


@dataclass(frozen=True)
class Migration:
    version: int
    name: str
    up_path: Path
    down_path: Path


MIGRATIONS = [
    Migration(
        version=1,
        name="semantic_actions",
        up_path=MIGRATIONS_DIR / "0001_semantic_actions.up.sql",
        down_path=MIGRATIONS_DIR / "0001_semantic_actions.down.sql",
    )
]


@dataclass(frozen=True)
class SemanticActionRecord:
    action_id: str
    session_id: str
    action_type: str
    selector: dict[str, Any]
    created_at: str
    updated_at: str
    args: dict[str, Any] = field(default_factory=dict)
    context: dict[str, Any] = field(default_factory=dict)
    confidence: float = 0.0
    source_event_ids: list[str] = field(default_factory=list)
    source_frame_ids: list[str] = field(default_factory=list)
    schema_version: str = SCHEMA_VERSION
    task_id: str | None = None
    turn_id: str | None = None
    trace_id: str | None = None
    step_id: str | None = None
    step_index: int | None = None
    source_path: str | None = None
    preferred_locator_type: str | None = None
    manual_review_required: bool = False
    legacy_coordinate: dict[str, Any] | None = None


@dataclass(frozen=True)
class SemanticActionTargetRecord:
    target_id: str
    target_role: str
    ordinal: int
    selector: dict[str, Any]
    created_at: str
    context: dict[str, Any] = field(default_factory=dict)
    locator_type: str | None = None
    confidence: float | None = None
    is_preferred: bool = False


@dataclass(frozen=True)
class SemanticActionAssertionRecord:
    assertion_id: str
    assertion_type: str
    assertion: dict[str, Any]
    created_at: str
    source: str
    is_required: bool = True
    ordinal: int = 0


@dataclass(frozen=True)
class SemanticActionExecutionLogRecord:
    execution_log_id: str
    status: str
    executed_at: str
    selector_hit_path: list[str] = field(default_factory=list)
    result: dict[str, Any] = field(default_factory=dict)
    trace_id: str | None = None
    component: str | None = None
    error_code: str | None = None
    duration_ms: int | None = None
    execution_log_path: str | None = None
    execution_result_path: str | None = None
    review_id: str | None = None


def _json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def _json_loads(value: str | None, default: Any) -> Any:
    if value is None or value == "":
        return default
    return json.loads(value)


def connect_sqlite(db_path: Path) -> sqlite3.Connection:
    db_path = Path(db_path)
    db_path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(db_path)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys=ON")
    return connection


class SemanticActionMigrationManager:
    def __init__(self, db_path: Path) -> None:
        self.db_path = Path(db_path)

    def applied_versions(self) -> list[int]:
        with connect_sqlite(self.db_path) as connection:
            self._ensure_migration_table(connection)
            rows = connection.execute(
                "SELECT version FROM _openstaff_schema_migrations ORDER BY version ASC"
            ).fetchall()
        return [int(row["version"]) for row in rows]

    def migrate_up(self) -> list[int]:
        applied: list[int] = []
        with connect_sqlite(self.db_path) as connection:
            self._ensure_migration_table(connection)
            existing = set(self._fetch_existing_versions(connection))
            for migration in MIGRATIONS:
                if migration.version in existing:
                    continue
                connection.executescript(migration.up_path.read_text(encoding="utf-8"))
                connection.execute(
                    """
                    INSERT INTO _openstaff_schema_migrations (version, name, applied_at)
                    VALUES (?, ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                    """,
                    (migration.version, migration.name),
                )
                applied.append(migration.version)
        return applied

    def migrate_down(self) -> list[int]:
        rolled_back: list[int] = []
        with connect_sqlite(self.db_path) as connection:
            self._ensure_migration_table(connection)
            existing = set(self._fetch_existing_versions(connection))
            for migration in reversed(MIGRATIONS):
                if migration.version not in existing:
                    continue
                connection.executescript(migration.down_path.read_text(encoding="utf-8"))
                connection.execute(
                    "DELETE FROM _openstaff_schema_migrations WHERE version = ?",
                    (migration.version,),
                )
                rolled_back.append(migration.version)
        return rolled_back

    @staticmethod
    def _ensure_migration_table(connection: sqlite3.Connection) -> None:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS _openstaff_schema_migrations (
                version INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at TEXT NOT NULL
            )
            """
        )

    @staticmethod
    def _fetch_existing_versions(connection: sqlite3.Connection) -> list[int]:
        rows = connection.execute(
            "SELECT version FROM _openstaff_schema_migrations ORDER BY version ASC"
        ).fetchall()
        return [int(row["version"]) for row in rows]


class SemanticActionRepository:
    def __init__(self, db_path: Path) -> None:
        self.db_path = Path(db_path)

    def clear_all(self) -> None:
        with connect_sqlite(self.db_path) as connection:
            connection.execute("DELETE FROM action_execution_logs")
            connection.execute("DELETE FROM action_assertions")
            connection.execute("DELETE FROM action_targets")
            connection.execute("DELETE FROM semantic_actions")

    def count_actions(self) -> int:
        with connect_sqlite(self.db_path) as connection:
            row = connection.execute("SELECT COUNT(*) AS count FROM semantic_actions").fetchone()
        return int(row["count"]) if row else 0

    def replace_action(
        self,
        action: SemanticActionRecord,
        *,
        targets: Iterable[SemanticActionTargetRecord] = (),
        assertions: Iterable[SemanticActionAssertionRecord] = (),
        execution_logs: Iterable[SemanticActionExecutionLogRecord] = (),
    ) -> None:
        target_records = list(targets)
        assertion_records = list(assertions)
        execution_log_records = list(execution_logs)

        with connect_sqlite(self.db_path) as connection:
            connection.execute(
                """
                INSERT INTO semantic_actions (
                    action_id,
                    schema_version,
                    session_id,
                    task_id,
                    turn_id,
                    trace_id,
                    step_id,
                    step_index,
                    action_type,
                    selector_json,
                    args_json,
                    context_json,
                    confidence,
                    source_event_ids,
                    source_frame_ids,
                    source_path,
                    preferred_locator_type,
                    manual_review_required,
                    legacy_coordinate_json,
                    created_at,
                    updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(action_id) DO UPDATE SET
                    schema_version = excluded.schema_version,
                    session_id = excluded.session_id,
                    task_id = excluded.task_id,
                    turn_id = excluded.turn_id,
                    trace_id = excluded.trace_id,
                    step_id = excluded.step_id,
                    step_index = excluded.step_index,
                    action_type = excluded.action_type,
                    selector_json = excluded.selector_json,
                    args_json = excluded.args_json,
                    context_json = excluded.context_json,
                    confidence = excluded.confidence,
                    source_event_ids = excluded.source_event_ids,
                    source_frame_ids = excluded.source_frame_ids,
                    source_path = excluded.source_path,
                    preferred_locator_type = excluded.preferred_locator_type,
                    manual_review_required = excluded.manual_review_required,
                    legacy_coordinate_json = excluded.legacy_coordinate_json,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at
                """,
                (
                    action.action_id,
                    action.schema_version,
                    action.session_id,
                    action.task_id,
                    action.turn_id,
                    action.trace_id,
                    action.step_id,
                    action.step_index,
                    action.action_type,
                    _json_dumps(action.selector),
                    _json_dumps(action.args),
                    _json_dumps(action.context),
                    action.confidence,
                    _json_dumps(action.source_event_ids),
                    _json_dumps(action.source_frame_ids),
                    action.source_path,
                    action.preferred_locator_type,
                    1 if action.manual_review_required else 0,
                    _json_dumps(action.legacy_coordinate) if action.legacy_coordinate is not None else None,
                    action.created_at,
                    action.updated_at,
                ),
            )

            for table_name in ("action_targets", "action_assertions", "action_execution_logs"):
                connection.execute(f"DELETE FROM {table_name} WHERE action_id = ?", (action.action_id,))

            if target_records:
                connection.executemany(
                    """
                    INSERT INTO action_targets (
                        target_id,
                        action_id,
                        target_role,
                        ordinal,
                        locator_type,
                        selector_json,
                        context_json,
                        confidence,
                        is_preferred,
                        created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        (
                            target.target_id,
                            action.action_id,
                            target.target_role,
                            target.ordinal,
                            target.locator_type,
                            _json_dumps(target.selector),
                            _json_dumps(target.context),
                            target.confidence,
                            1 if target.is_preferred else 0,
                            target.created_at,
                        )
                        for target in target_records
                    ],
                )

            if assertion_records:
                connection.executemany(
                    """
                    INSERT INTO action_assertions (
                        assertion_id,
                        action_id,
                        assertion_type,
                        assertion_json,
                        is_required,
                        ordinal,
                        source,
                        created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        (
                            assertion.assertion_id,
                            action.action_id,
                            assertion.assertion_type,
                            _json_dumps(assertion.assertion),
                            1 if assertion.is_required else 0,
                            assertion.ordinal,
                            assertion.source,
                            assertion.created_at,
                        )
                        for assertion in assertion_records
                    ],
                )

            if execution_log_records:
                connection.executemany(
                    """
                    INSERT INTO action_execution_logs (
                        execution_log_id,
                        action_id,
                        trace_id,
                        component,
                        status,
                        error_code,
                        selector_hit_path_json,
                        result_json,
                        duration_ms,
                        execution_log_path,
                        execution_result_path,
                        review_id,
                        executed_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        (
                            execution_log.execution_log_id,
                            action.action_id,
                            execution_log.trace_id,
                            execution_log.component,
                            execution_log.status,
                            execution_log.error_code,
                            _json_dumps(execution_log.selector_hit_path),
                            _json_dumps(execution_log.result),
                            execution_log.duration_ms,
                            execution_log.execution_log_path,
                            execution_log.execution_result_path,
                            execution_log.review_id,
                            execution_log.executed_at,
                        )
                        for execution_log in execution_log_records
                    ],
                )

    def get_action(self, action_id: str) -> dict[str, Any] | None:
        with connect_sqlite(self.db_path) as connection:
            row = connection.execute(
                "SELECT * FROM semantic_actions WHERE action_id = ?",
                (action_id,),
            ).fetchone()
            if row is None:
                return None
            return self._hydrate_action(connection, row)

    def list_actions(
        self,
        *,
        session_id: str | None = None,
        action_type: str | None = None,
        limit: int | None = None,
    ) -> list[dict[str, Any]]:
        clauses: list[str] = []
        params: list[Any] = []

        if session_id:
            clauses.append("session_id = ?")
            params.append(session_id)
        if action_type:
            clauses.append("action_type = ?")
            params.append(action_type)

        query = "SELECT * FROM semantic_actions"
        if clauses:
            query += " WHERE " + " AND ".join(clauses)
        query += " ORDER BY created_at ASC, action_id ASC"
        if limit is not None:
            query += " LIMIT ?"
            params.append(limit)

        with connect_sqlite(self.db_path) as connection:
            rows = connection.execute(query, tuple(params)).fetchall()
            return [self._hydrate_action(connection, row) for row in rows]

    def _hydrate_action(self, connection: sqlite3.Connection, row: sqlite3.Row) -> dict[str, Any]:
        payload = dict(row)
        payload["selector_json"] = _json_loads(payload.get("selector_json"), {})
        payload["args_json"] = _json_loads(payload.get("args_json"), {})
        payload["context_json"] = _json_loads(payload.get("context_json"), {})
        payload["source_event_ids"] = _json_loads(payload.get("source_event_ids"), [])
        payload["source_frame_ids"] = _json_loads(payload.get("source_frame_ids"), [])
        payload["legacy_coordinate_json"] = _json_loads(payload.get("legacy_coordinate_json"), None)
        payload["manual_review_required"] = bool(payload.get("manual_review_required"))
        payload["targets"] = self._load_targets(connection, payload["action_id"])
        payload["assertions"] = self._load_assertions(connection, payload["action_id"])
        payload["execution_logs"] = self._load_execution_logs(connection, payload["action_id"])
        return payload

    def _load_targets(self, connection: sqlite3.Connection, action_id: str) -> list[dict[str, Any]]:
        rows = connection.execute(
            """
            SELECT *
            FROM action_targets
            WHERE action_id = ?
            ORDER BY ordinal ASC, target_id ASC
            """,
            (action_id,),
        ).fetchall()
        targets: list[dict[str, Any]] = []
        for row in rows:
            payload = dict(row)
            payload["selector_json"] = _json_loads(payload.get("selector_json"), {})
            payload["context_json"] = _json_loads(payload.get("context_json"), {})
            payload["is_preferred"] = bool(payload.get("is_preferred"))
            targets.append(payload)
        return targets

    def _load_assertions(self, connection: sqlite3.Connection, action_id: str) -> list[dict[str, Any]]:
        rows = connection.execute(
            """
            SELECT *
            FROM action_assertions
            WHERE action_id = ?
            ORDER BY ordinal ASC, assertion_id ASC
            """,
            (action_id,),
        ).fetchall()
        assertions: list[dict[str, Any]] = []
        for row in rows:
            payload = dict(row)
            payload["assertion_json"] = _json_loads(payload.get("assertion_json"), {})
            payload["is_required"] = bool(payload.get("is_required"))
            assertions.append(payload)
        return assertions

    def _load_execution_logs(self, connection: sqlite3.Connection, action_id: str) -> list[dict[str, Any]]:
        rows = connection.execute(
            """
            SELECT *
            FROM action_execution_logs
            WHERE action_id = ?
            ORDER BY executed_at ASC, execution_log_id ASC
            """,
            (action_id,),
        ).fetchall()
        execution_logs: list[dict[str, Any]] = []
        for row in rows:
            payload = dict(row)
            payload["selector_hit_path_json"] = _json_loads(payload.get("selector_hit_path_json"), [])
            payload["result_json"] = _json_loads(payload.get("result_json"), {})
            execution_logs.append(payload)
        return execution_logs
