import Foundation

public enum PreferenceSignalMergeConflictTag: String, Codable, CaseIterable, Sendable {
    case opposingPolarity = "opposing_polarity"
    case divergentEvaluativeDecision = "divergent_evaluative_decision"
    case divergentHint = "divergent_hint"
    case divergentProposedAction = "divergent_proposed_action"
}

public struct PreferenceSignalMergeEntry: Equatable, Sendable {
    public let signal: PreferenceSignal
    public let sourceSignalIds: [String]
    public let sourceEvidenceIds: [String]
    public let mergedConfidence: Double
    public let conflictTags: [PreferenceSignalMergeConflictTag]

    public init(
        signal: PreferenceSignal,
        sourceSignalIds: [String],
        sourceEvidenceIds: [String],
        mergedConfidence: Double,
        conflictTags: [PreferenceSignalMergeConflictTag]
    ) {
        self.signal = signal
        self.sourceSignalIds = Array(Set(sourceSignalIds)).sorted()
        self.sourceEvidenceIds = Array(Set(sourceEvidenceIds)).sorted()
        self.mergedConfidence = mergedConfidence
        self.conflictTags = Array(Set(conflictTags)).sorted {
            $0.rawValue < $1.rawValue
        }
    }
}

public struct PreferenceSignalMergeResult: Equatable, Sendable {
    public let entries: [PreferenceSignalMergeEntry]

    public init(entries: [PreferenceSignalMergeEntry]) {
        self.entries = entries.sorted {
            ($0.signal.timestamp, $0.signal.signalId) < ($1.signal.timestamp, $1.signal.signalId)
        }
    }

    public var mergedSignals: [PreferenceSignal] {
        entries.map(\.signal)
    }
}

public enum PreferenceSignalMerger {
    public static func merge(_ signals: [PreferenceSignal]) -> PreferenceSignalMergeResult {
        let dedupedSignals = dedupeSignalsByID(signals)
        let groupedSignals = Dictionary(grouping: dedupedSignals, by: mergeKey(for:))

        var entries = groupedSignals.values.map(mergeGroup(_:))
        let baseConflictKeys = Dictionary(grouping: entries.indices, by: { baseConflictKey(for: entries[$0].signal) })

        for indices in baseConflictKeys.values {
            let polarities = Set(indices.map { entries[$0].signal.polarity })
            guard polarities.count > 1 else {
                continue
            }

            for index in indices {
                entries[index] = appendingConflictTag(.opposingPolarity, to: entries[index])
            }
        }

        return PreferenceSignalMergeResult(entries: entries)
    }

    public static func mergedSignals(from signals: [PreferenceSignal]) -> [PreferenceSignal] {
        merge(signals).mergedSignals
    }

    private static func mergeGroup(_ signals: [PreferenceSignal]) -> PreferenceSignalMergeEntry {
        let orderedSignals = signals.sorted(by: sortsBefore)
        let representative = orderedSignals.last ?? signals[0]
        let mergedConfidence = orderedSignals.isEmpty
            ? representative.confidence
            : orderedSignals.map(\.confidence).reduce(0, +) / Double(orderedSignals.count)
        let mergedEvidenceIds = orderedSignals.flatMap(\.evidenceIds)
        let evaluativeDecisions = Set(orderedSignals.map(\.evaluativeDecision))
        let hints = Set(orderedSignals.compactMap { normalizedOptionalString($0.hint) })
        let proposedActions = Set(orderedSignals.compactMap { normalizedOptionalString($0.proposedAction) })
        let timestamp = orderedSignals.map(\.timestamp).max() ?? representative.timestamp

        var conflictTags: [PreferenceSignalMergeConflictTag] = []
        if evaluativeDecisions.count > 1 {
            conflictTags.append(.divergentEvaluativeDecision)
        }
        if hints.count > 1 {
            conflictTags.append(.divergentHint)
        }
        if proposedActions.count > 1 {
            conflictTags.append(.divergentProposedAction)
        }

        let mergedSignal = PreferenceSignal(
            schemaVersion: representative.schemaVersion,
            signalId: representative.signalId,
            turnId: representative.turnId,
            traceId: representative.traceId,
            sessionId: representative.sessionId,
            taskId: representative.taskId,
            stepId: representative.stepId,
            type: representative.type,
            evaluativeDecision: representative.evaluativeDecision,
            polarity: representative.polarity,
            scope: representative.scope,
            hint: representative.hint,
            confidence: mergedConfidence,
            evidenceIds: Array(Set(mergedEvidenceIds)).sorted(),
            proposedAction: representative.proposedAction,
            promotionStatus: representative.promotionStatus,
            timestamp: timestamp
        )

        return PreferenceSignalMergeEntry(
            signal: mergedSignal,
            sourceSignalIds: orderedSignals.map(\.signalId),
            sourceEvidenceIds: mergedEvidenceIds,
            mergedConfidence: mergedConfidence,
            conflictTags: conflictTags
        )
    }

    private static func dedupeSignalsByID(_ signals: [PreferenceSignal]) -> [PreferenceSignal] {
        var dedupedByID: [String: PreferenceSignal] = [:]
        for signal in signals {
            if let existing = dedupedByID[signal.signalId] {
                dedupedByID[signal.signalId] = preferredSignal(between: existing, and: signal)
            } else {
                dedupedByID[signal.signalId] = signal
            }
        }
        return dedupedByID.values.sorted(by: sortsBefore)
    }

    private static func preferredSignal(
        between lhs: PreferenceSignal,
        and rhs: PreferenceSignal
    ) -> PreferenceSignal {
        sortsBefore(lhs, rhs) ? rhs : lhs
    }

    private static func sortsBefore(_ lhs: PreferenceSignal, _ rhs: PreferenceSignal) -> Bool {
        let lhsKey = (
            promotionStatusPriority(lhs.promotionStatus),
            lhs.confidence,
            lhs.timestamp,
            lhs.signalId
        )
        let rhsKey = (
            promotionStatusPriority(rhs.promotionStatus),
            rhs.confidence,
            rhs.timestamp,
            rhs.signalId
        )
        return lhsKey < rhsKey
    }

    private static func promotionStatusPriority(_ status: PreferenceSignalPromotionStatus) -> Int {
        switch status {
        case .superseded:
            return 0
        case .rejected:
            return 1
        case .candidate:
            return 2
        case .confirmed:
            return 3
        }
    }

    private static func mergeKey(for signal: PreferenceSignal) -> String {
        [
            signal.sessionId,
            signal.turnId,
            scopeKey(for: signal.scope),
            signal.type.rawValue,
            signal.polarity.rawValue
        ].joined(separator: "|")
    }

    private static func baseConflictKey(for signal: PreferenceSignal) -> String {
        [
            signal.sessionId,
            signal.turnId,
            scopeKey(for: signal.scope),
            signal.type.rawValue
        ].joined(separator: "|")
    }

    private static func scopeKey(for scope: PreferenceSignalScopeReference) -> String {
        [
            scope.level.rawValue,
            scope.appBundleId ?? "",
            scope.appName ?? "",
            scope.taskFamily ?? "",
            scope.skillFamily ?? "",
            scope.windowPattern ?? ""
        ].joined(separator: "§")
    }

    private static func normalizedOptionalString(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func appendingConflictTag(
        _ tag: PreferenceSignalMergeConflictTag,
        to entry: PreferenceSignalMergeEntry
    ) -> PreferenceSignalMergeEntry {
        PreferenceSignalMergeEntry(
            signal: entry.signal,
            sourceSignalIds: entry.sourceSignalIds,
            sourceEvidenceIds: entry.sourceEvidenceIds,
            mergedConfidence: entry.mergedConfidence,
            conflictTags: entry.conflictTags + [tag]
        )
    }
}
