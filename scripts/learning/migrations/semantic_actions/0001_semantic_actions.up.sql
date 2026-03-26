CREATE TABLE IF NOT EXISTS _openstaff_schema_migrations (
    version INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    applied_at TEXT NOT NULL
);

CREATE TABLE semantic_actions (
    action_id TEXT PRIMARY KEY,
    schema_version TEXT NOT NULL,
    session_id TEXT NOT NULL,
    task_id TEXT,
    turn_id TEXT,
    trace_id TEXT,
    step_id TEXT,
    step_index INTEGER,
    action_type TEXT NOT NULL,
    selector_json TEXT NOT NULL,
    args_json TEXT NOT NULL DEFAULT '{}',
    context_json TEXT NOT NULL DEFAULT '{}',
    confidence REAL NOT NULL DEFAULT 0,
    source_event_ids TEXT NOT NULL DEFAULT '[]',
    source_frame_ids TEXT NOT NULL DEFAULT '[]',
    source_path TEXT,
    preferred_locator_type TEXT,
    manual_review_required INTEGER NOT NULL DEFAULT 0,
    legacy_coordinate_json TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX idx_semantic_actions_session_type
    ON semantic_actions (session_id, action_type);

CREATE INDEX idx_semantic_actions_turn_id
    ON semantic_actions (turn_id);

CREATE INDEX idx_semantic_actions_trace_id
    ON semantic_actions (trace_id);

CREATE TABLE action_targets (
    target_id TEXT PRIMARY KEY,
    action_id TEXT NOT NULL,
    target_role TEXT NOT NULL,
    ordinal INTEGER NOT NULL,
    locator_type TEXT,
    selector_json TEXT NOT NULL,
    context_json TEXT NOT NULL DEFAULT '{}',
    confidence REAL,
    is_preferred INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    FOREIGN KEY (action_id) REFERENCES semantic_actions (action_id) ON DELETE CASCADE
);

CREATE INDEX idx_action_targets_action_ordinal
    ON action_targets (action_id, ordinal);

CREATE TABLE action_assertions (
    assertion_id TEXT PRIMARY KEY,
    action_id TEXT NOT NULL,
    assertion_type TEXT NOT NULL,
    assertion_json TEXT NOT NULL,
    is_required INTEGER NOT NULL DEFAULT 1,
    ordinal INTEGER NOT NULL DEFAULT 0,
    source TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (action_id) REFERENCES semantic_actions (action_id) ON DELETE CASCADE
);

CREATE INDEX idx_action_assertions_action_ordinal
    ON action_assertions (action_id, ordinal);

CREATE TABLE action_execution_logs (
    execution_log_id TEXT PRIMARY KEY,
    action_id TEXT NOT NULL,
    trace_id TEXT,
    component TEXT,
    status TEXT NOT NULL,
    error_code TEXT,
    selector_hit_path_json TEXT NOT NULL DEFAULT '[]',
    result_json TEXT NOT NULL DEFAULT '{}',
    duration_ms INTEGER,
    execution_log_path TEXT,
    execution_result_path TEXT,
    review_id TEXT,
    executed_at TEXT NOT NULL,
    FOREIGN KEY (action_id) REFERENCES semantic_actions (action_id) ON DELETE CASCADE
);

CREATE INDEX idx_action_execution_logs_action_time
    ON action_execution_logs (action_id, executed_at);
