import Foundation
import SQLite3

typealias SemanticJSONObject = [String: Any]

enum SemanticActionStoreError: LocalizedError {
    case openDatabase(String)
    case prepareStatement(String)
    case queryFailed(String)
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .openDatabase(let message):
            return "Semantic action store open failed: \(message)"
        case .prepareStatement(let message):
            return "Semantic action store prepare failed: \(message)"
        case .queryFailed(let message):
            return "Semantic action store query failed: \(message)"
        case .invalidJSON(let message):
            return "Semantic action store JSON decode failed: \(message)"
        }
    }
}

struct SemanticActionStoreTargetRecord {
    let targetId: String
    let targetRole: String
    let ordinal: Int
    let locatorType: String?
    let selector: SemanticJSONObject
    let isPreferred: Bool
}

struct SemanticActionStoreAssertionRecord {
    let assertionId: String
    let assertionType: String
    let payload: SemanticJSONObject
    let isRequired: Bool
    let ordinal: Int
}

struct SemanticActionStoreAction {
    let actionId: String
    let sessionId: String
    let taskId: String?
    let traceId: String?
    let stepId: String?
    let actionType: String
    let selector: SemanticJSONObject
    let args: SemanticJSONObject
    let context: SemanticJSONObject
    let preferredLocatorType: String?
    let manualReviewRequired: Bool
    let createdAt: String
    let updatedAt: String
    let targets: [SemanticActionStoreTargetRecord]
    let assertions: [SemanticActionStoreAssertionRecord]
}

struct SemanticActionStoreExecutionLogRecord {
    let executionLogId: String
    let actionId: String
    let traceId: String?
    let component: String
    let status: String
    let errorCode: String?
    let selectorHitPath: [String]
    let result: SemanticJSONObject
    let durationMs: Int
    let executedAt: String
}

final class SemanticActionSQLiteStore {
    private let databaseURL: URL

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    func fetchAction(actionId: String) throws -> SemanticActionStoreAction? {
        try withDatabase { database in
            let statement = try prepare(
                database,
                sql: """
                SELECT
                    action_id,
                    session_id,
                    task_id,
                    trace_id,
                    step_id,
                    action_type,
                    selector_json,
                    args_json,
                    context_json,
                    preferred_locator_type,
                    manual_review_required,
                    created_at,
                    updated_at
                FROM semantic_actions
                WHERE action_id = ?
                LIMIT 1
                """
            )
            defer { sqlite3_finalize(statement) }

            bindText(actionId, to: statement, index: 1)
            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else {
                if result == SQLITE_DONE {
                    return nil
                }
                throw SemanticActionStoreError.queryFailed(lastErrorMessage(database))
            }

            let fetchedActionId = text(statement, index: 0) ?? actionId
            return SemanticActionStoreAction(
                actionId: fetchedActionId,
                sessionId: text(statement, index: 1) ?? "",
                taskId: text(statement, index: 2),
                traceId: text(statement, index: 3),
                stepId: text(statement, index: 4),
                actionType: text(statement, index: 5) ?? "",
                selector: try object(statement, index: 6, label: "selector_json"),
                args: try object(statement, index: 7, label: "args_json"),
                context: try object(statement, index: 8, label: "context_json"),
                preferredLocatorType: text(statement, index: 9),
                manualReviewRequired: integer(statement, index: 10) != 0,
                createdAt: text(statement, index: 11) ?? "",
                updatedAt: text(statement, index: 12) ?? "",
                targets: try fetchTargets(database: database, actionId: fetchedActionId),
                assertions: try fetchAssertions(database: database, actionId: fetchedActionId)
            )
        }
    }

    func appendExecutionLog(_ log: SemanticActionStoreExecutionLogRecord) throws {
        try withDatabase { database in
            let statement = try prepare(
                database,
                sql: """
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
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, ?)
                """
            )
            defer { sqlite3_finalize(statement) }

            bindText(log.executionLogId, to: statement, index: 1)
            bindText(log.actionId, to: statement, index: 2)
            bindOptionalText(log.traceId, to: statement, index: 3)
            bindText(log.component, to: statement, index: 4)
            bindText(log.status, to: statement, index: 5)
            bindOptionalText(log.errorCode, to: statement, index: 6)
            bindText(jsonString(log.selectorHitPath), to: statement, index: 7)
            bindText(jsonString(log.result), to: statement, index: 8)
            sqlite3_bind_int64(statement, 9, sqlite3_int64(log.durationMs))
            bindText(log.executedAt, to: statement, index: 10)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SemanticActionStoreError.queryFailed(lastErrorMessage(database))
            }
        }
    }

    private func fetchTargets(
        database: OpaquePointer?,
        actionId: String
    ) throws -> [SemanticActionStoreTargetRecord] {
        let statement = try prepare(
            database,
            sql: """
            SELECT target_id, target_role, ordinal, locator_type, selector_json, is_preferred
            FROM action_targets
            WHERE action_id = ?
            ORDER BY ordinal ASC, target_id ASC
            """
        )
        defer { sqlite3_finalize(statement) }

        bindText(actionId, to: statement, index: 1)
        var rows: [SemanticActionStoreTargetRecord] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                break
            }
            guard result == SQLITE_ROW else {
                throw SemanticActionStoreError.queryFailed(lastErrorMessage(database))
            }
            rows.append(
                SemanticActionStoreTargetRecord(
                    targetId: text(statement, index: 0) ?? "",
                    targetRole: text(statement, index: 1) ?? "",
                    ordinal: Int(integer(statement, index: 2)),
                    locatorType: text(statement, index: 3),
                    selector: try object(statement, index: 4, label: "action_targets.selector_json"),
                    isPreferred: integer(statement, index: 5) != 0
                )
            )
        }
        return rows
    }

    private func fetchAssertions(
        database: OpaquePointer?,
        actionId: String
    ) throws -> [SemanticActionStoreAssertionRecord] {
        let statement = try prepare(
            database,
            sql: """
            SELECT assertion_id, assertion_type, assertion_json, is_required, ordinal
            FROM action_assertions
            WHERE action_id = ?
            ORDER BY ordinal ASC, assertion_id ASC
            """
        )
        defer { sqlite3_finalize(statement) }

        bindText(actionId, to: statement, index: 1)
        var rows: [SemanticActionStoreAssertionRecord] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                break
            }
            guard result == SQLITE_ROW else {
                throw SemanticActionStoreError.queryFailed(lastErrorMessage(database))
            }
            rows.append(
                SemanticActionStoreAssertionRecord(
                    assertionId: text(statement, index: 0) ?? "",
                    assertionType: text(statement, index: 1) ?? "",
                    payload: try object(statement, index: 2, label: "action_assertions.assertion_json"),
                    isRequired: integer(statement, index: 3) != 0,
                    ordinal: Int(integer(statement, index: 4))
                )
            )
        }
        return rows
    }

    private func withDatabase<T>(_ body: (OpaquePointer?) throws -> T) throws -> T {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            defer { sqlite3_close(database) }
            throw SemanticActionStoreError.openDatabase(lastErrorMessage(database))
        }
        defer { sqlite3_close(database) }
        return try body(database)
    }

    private func prepare(_ database: OpaquePointer?, sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SemanticActionStoreError.prepareStatement(lastErrorMessage(database))
        }
        return statement
    }

    private func text(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: pointer)
    }

    private func integer(_ statement: OpaquePointer?, index: Int32) -> Int64 {
        sqlite3_column_int64(statement, index)
    }

    private func object(_ statement: OpaquePointer?, index: Int32, label: String) throws -> SemanticJSONObject {
        guard let raw = text(statement, index: index), !raw.isEmpty else {
            return [:]
        }
        guard let data = raw.data(using: .utf8),
              let value = try JSONSerialization.jsonObject(with: data) as? SemanticJSONObject else {
            throw SemanticActionStoreError.invalidJSON(label)
        }
        return value
    }

    private func bindText(_ value: String, to statement: OpaquePointer?, index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransientDestructor)
    }

    private func bindOptionalText(_ value: String?, to statement: OpaquePointer?, index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        bindText(value, to: statement, index: index)
    }

    private func jsonString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func lastErrorMessage(_ database: OpaquePointer?) -> String {
        guard let database else {
            return "unknown sqlite error"
        }
        return String(cString: sqlite3_errmsg(database))
    }
}

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
