import Foundation

public enum DirectiveHintConsumer: String, Codable, CaseIterable, Sendable {
    case assistRerank = "assist_rerank"
    case skillMapper = "skill_mapper"
    case repairPlanner = "repair_planner"
    case reviewSuggestion = "review_suggestion"

    fileprivate var sortOrder: Int {
        switch self {
        case .assistRerank:
            return 0
        case .skillMapper:
            return 1
        case .repairPlanner:
            return 2
        case .reviewSuggestion:
            return 3
        }
    }
}

public struct DirectiveHint: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let hintId: String
    public let signalId: String
    public let turnId: String
    public let traceId: String?
    public let sessionId: String
    public let taskId: String
    public let stepId: String
    public let consumer: DirectiveHintConsumer
    public let signalType: PreferenceSignalType
    public let scope: PreferenceSignalScopeReference
    public let hint: String
    public let proposedAction: String
    public let confidence: Double
    public let evidenceIds: [String]
    public let createdAt: String

    public init(
        schemaVersion: String = "openstaff.learning.directive-hint.v0",
        hintId: String,
        signalId: String,
        turnId: String,
        traceId: String? = nil,
        sessionId: String,
        taskId: String,
        stepId: String,
        consumer: DirectiveHintConsumer,
        signalType: PreferenceSignalType,
        scope: PreferenceSignalScopeReference,
        hint: String,
        proposedAction: String,
        confidence: Double,
        evidenceIds: [String],
        createdAt: String
    ) {
        self.schemaVersion = schemaVersion
        self.hintId = hintId
        self.signalId = signalId
        self.turnId = turnId
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.stepId = stepId
        self.consumer = consumer
        self.signalType = signalType
        self.scope = scope
        self.hint = hint
        self.proposedAction = proposedAction
        self.confidence = confidence
        self.evidenceIds = evidenceIds
        self.createdAt = createdAt
    }
}

public enum DirectiveHintBuilder {
    public static func build(from signal: PreferenceSignal) -> [DirectiveHint] {
        build(from: [signal])
    }

    public static func build(from signals: [PreferenceSignal]) -> [DirectiveHint] {
        let mergedEntries = PreferenceSignalMerger.merge(signals).entries

        var seenHintKeys = Set<String>()
        var hints: [DirectiveHint] = []

        for entry in mergedEntries {
            guard !entry.conflictTags.contains(.opposingPolarity),
                  !entry.conflictTags.contains(.divergentProposedAction) else {
                continue
            }

            let signal = entry.signal
            guard isAcceptedDirectiveSignal(signal),
                  let hint = normalizedOptionalString(signal.hint),
                  let proposedAction = normalizedOptionalString(signal.proposedAction) else {
                continue
            }

            let consumers = directiveConsumers(for: signal).sorted {
                $0.sortOrder < $1.sortOrder
            }

            for consumer in consumers {
                let dedupeKey = "\(signal.signalId)|\(consumer.rawValue)"
                guard seenHintKeys.insert(dedupeKey).inserted else {
                    continue
                }

                hints.append(
                    DirectiveHint(
                        hintId: derivedHintId(signalId: signal.signalId, consumer: consumer),
                        signalId: signal.signalId,
                        turnId: signal.turnId,
                        traceId: signal.traceId,
                        sessionId: signal.sessionId,
                        taskId: signal.taskId,
                        stepId: signal.stepId,
                        consumer: consumer,
                        signalType: signal.type,
                        scope: signal.scope,
                        hint: hint,
                        proposedAction: proposedAction,
                        confidence: entry.mergedConfidence,
                        evidenceIds: entry.sourceEvidenceIds,
                        createdAt: signal.timestamp
                    )
                )
            }
        }

        return hints
    }

    public static func directiveConsumers(for signal: PreferenceSignal) -> [DirectiveHintConsumer] {
        guard signal.hasDirectivePayload else {
            return []
        }

        var consumers = Set<DirectiveHintConsumer>()
        let proposedAction = signal.proposedAction?.lowercased()

        switch signal.type {
        case .outcome:
            break
        case .procedure:
            consumers.formUnion([.assistRerank, .skillMapper, .reviewSuggestion])
        case .locator:
            consumers.formUnion([.skillMapper, .repairPlanner, .reviewSuggestion])
        case .style:
            consumers.formUnion([.assistRerank, .skillMapper, .reviewSuggestion])
        case .risk:
            consumers.formUnion([.assistRerank, .skillMapper, .reviewSuggestion])
        case .repair:
            consumers.formUnion([.repairPlanner, .reviewSuggestion])
        }

        if containsAnyToken(
            proposedAction,
            tokens: ["locator", "anchor", "relocalize", "updateskilllocator", "refresh_skill_locator"]
        ) {
            consumers.formUnion([.skillMapper, .repairPlanner])
        }

        if containsAnyToken(
            proposedAction,
            tokens: ["repair", "replay", "reteach", "retry"]
        ) {
            consumers.insert(.repairPlanner)
        }

        if containsAnyToken(
            proposedAction,
            tokens: ["confirmation", "confirm", "blocked", "guard", "risk"]
        ) {
            consumers.formUnion([.assistRerank, .skillMapper, .reviewSuggestion])
        }

        return Array(consumers)
    }

    private static func isAcceptedDirectiveSignal(_ signal: PreferenceSignal) -> Bool {
        guard signal.type != .outcome else {
            return false
        }

        guard signal.hasDirectivePayload else {
            return false
        }

        switch signal.promotionStatus {
        case .candidate, .confirmed:
            return true
        case .rejected, .superseded:
            return false
        }
    }

    private static func derivedHintId(
        signalId: String,
        consumer: DirectiveHintConsumer
    ) -> String {
        "directive-hint-\(consumer.rawValue)-\(sanitizedToken(signalId))"
    }

    private static func normalizedOptionalString(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func containsAnyToken(
        _ value: String?,
        tokens: [String]
    ) -> Bool {
        guard let value else {
            return false
        }

        return tokens.contains { token in
            value.localizedCaseInsensitiveContains(token)
        }
    }

    private static func sanitizedToken(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let token = String(scalars)
        return token.isEmpty ? "directive-hint" : token
    }
}
