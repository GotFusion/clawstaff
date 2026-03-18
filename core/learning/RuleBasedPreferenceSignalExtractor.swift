import Foundation

public struct PreferenceSignalExtractionInput: Equatable {
    public let turn: InteractionTurn
    public let evidence: [NextStateEvidence]
    public let taskFamily: String?
    public let extractedAt: String?

    public init(
        turn: InteractionTurn,
        evidence: [NextStateEvidence],
        taskFamily: String? = nil,
        extractedAt: String? = nil
    ) {
        self.turn = turn
        self.evidence = evidence
        self.taskFamily = taskFamily
        self.extractedAt = extractedAt
    }
}

public enum RuleBasedPreferenceSignalExtractor {
    public static func extract(_ input: PreferenceSignalExtractionInput) -> [PreferenceSignal] {
        let orderedEvidence = input.evidence.sorted {
            ($0.timestamp, $0.evidenceId) < ($1.timestamp, $1.evidenceId)
        }

        let signals = orderedEvidence.flatMap { evidence in
            extractSignals(from: evidence, input: input)
        }

        return signals.sorted {
            ($0.timestamp, $0.signalId) < ($1.timestamp, $1.signalId)
        }
    }

    public static func extract(
        turn: InteractionTurn,
        evidence: [NextStateEvidence],
        taskFamily: String? = nil,
        extractedAt: String? = nil
    ) -> [PreferenceSignal] {
        extract(
            PreferenceSignalExtractionInput(
                turn: turn,
                evidence: evidence,
                taskFamily: taskFamily,
                extractedAt: extractedAt
            )
        )
    }

    public static func signalFileURL(
        for signal: PreferenceSignal,
        signalsRootDirectory: URL
    ) -> URL {
        let dateDirectory = dateKey(from: signal.timestamp)
        return signalsRootDirectory
            .appendingPathComponent(dateDirectory, isDirectory: true)
            .appendingPathComponent(signal.sessionId, isDirectory: true)
            .appendingPathComponent("\(signal.turnId).json", isDirectory: false)
    }

    @discardableResult
    public static func write(
        _ signals: [PreferenceSignal],
        signalsRootDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let groupedSignals = Dictionary(grouping: signals) { signal in
            "\(signal.sessionId)\u{0}\(signal.turnId)"
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]

        return try groupedSignals.keys.sorted().map { key in
            guard let group = groupedSignals[key], let firstSignal = group.first else {
                throw CocoaError(.fileWriteUnknown)
            }

            let orderedGroup = group.sorted {
                ($0.timestamp, $0.signalId) < ($1.timestamp, $1.signalId)
            }
            let fileURL = signalFileURL(for: firstSignal, signalsRootDirectory: signalsRootDirectory)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let payload = try encoder.encode(orderedGroup)
            try payload.write(to: fileURL, options: .atomic)
            return fileURL
        }
    }

    private static func extractSignals(
        from evidence: NextStateEvidence,
        input: PreferenceSignalExtractionInput
    ) -> [PreferenceSignal] {
        switch evidence.source {
        case .teacherReview:
            return extractTeacherReviewSignals(from: evidence, input: input)
        case .replayVerify:
            return extractReplayVerifySignals(from: evidence, input: input)
        case .driftDetection:
            return extractDriftSignals(from: evidence, input: input)
        case .benchmarkResult:
            return extractBenchmarkSignals(from: evidence, input: input)
        case .executionRuntime:
            return extractSafetyBlockSignals(from: evidence, input: input)
        case .chatgptSuggestion:
            return []
        }
    }

    private static func extractTeacherReviewSignals(
        from evidence: NextStateEvidence,
        input: PreferenceSignalExtractionInput
    ) -> [PreferenceSignal] {
        guard let action = teacherReviewAction(for: evidence) else {
            return []
        }

        switch action {
        case .approved, .rejected, .needsRevision:
            return [
                makeSignal(
                    type: .outcome,
                    evidence: evidence,
                    input: input,
                    evaluativeDecision: action == .approved ? .pass : .fail,
                    polarity: action == .approved ? .reinforce : .discourage,
                    scope: taskFamilyScope(for: input),
                    hint: nil,
                    proposedAction: nil
                )
            ]
        case .fixLocator, .reteach:
            let directive = evidence.directiveCandidate
            let proposedAction = directive?.repairActionType ?? directive?.action ?? defaultRepairAction(for: action)
            return [
                makeSignal(
                    type: .repair,
                    evidence: evidence,
                    input: input,
                    evaluativeDecision: .fail,
                    polarity: .discourage,
                    scope: taskFamilyScope(for: input),
                    hint: directive?.hint ?? bestHint(for: evidence),
                    proposedAction: proposedAction
                )
            ]
        case .tooDangerous:
            return [
                makeSignal(
                    type: .risk,
                    evidence: evidence,
                    input: input,
                    evaluativeDecision: .fail,
                    polarity: .discourage,
                    scope: appScope(for: input.turn),
                    hint: "Require teacher confirmation before executing similar high-risk steps.",
                    proposedAction: "require_teacher_confirmation"
                )
            ]
        case .wrongOrder:
            return [
                makeSignal(
                    type: .procedure,
                    evidence: evidence,
                    input: input,
                    evaluativeDecision: .fail,
                    polarity: .discourage,
                    scope: taskFamilyScope(for: input),
                    hint: nil,
                    proposedAction: nil
                )
            ]
        case .wrongStyle:
            return [
                makeSignal(
                    type: .style,
                    evidence: evidence,
                    input: input,
                    evaluativeDecision: .fail,
                    polarity: .discourage,
                    scope: .global(),
                    hint: nil,
                    proposedAction: nil
                )
            ]
        }
    }

    private static func extractReplayVerifySignals(
        from evidence: NextStateEvidence,
        input: PreferenceSignalExtractionInput
    ) -> [PreferenceSignal] {
        guard indicatesLocatorIssue(evidence) else {
            return []
        }

        let directive = evidence.directiveCandidate
        return [
            makeSignal(
                type: .locator,
                evidence: evidence,
                input: input,
                evaluativeDecision: .fail,
                polarity: .discourage,
                scope: appScope(for: input.turn),
                hint: directive?.hint ?? bestHint(for: evidence),
                proposedAction: directive?.repairActionType ?? directive?.action ?? "repair_locator"
            )
        ]
    }

    private static func extractDriftSignals(
        from evidence: NextStateEvidence,
        input: PreferenceSignalExtractionInput
    ) -> [PreferenceSignal] {
        var signals: [PreferenceSignal] = []
        let directive = evidence.directiveCandidate

        if indicatesLocatorIssue(evidence) {
            signals.append(
                makeSignal(
                    type: .locator,
                    evidence: evidence,
                    input: input,
                    evaluativeDecision: .fail,
                    polarity: .discourage,
                    scope: appScope(for: input.turn),
                    hint: directive?.hint ?? bestHint(for: evidence),
                    proposedAction: directive?.repairActionType ?? directive?.action ?? "repair_locator"
                )
            )
        }

        if let directive {
            let proposedAction = directive.repairActionType ?? directive.action
            if !proposedAction.isEmpty {
            signals.append(
                makeSignal(
                    type: .repair,
                    evidence: evidence,
                    input: input,
                    evaluativeDecision: .fail,
                    polarity: .discourage,
                    scope: taskFamilyScope(for: input),
                    hint: directive.hint,
                    proposedAction: proposedAction
                )
            )
            }
        }

        return signals
    }

    private static func extractBenchmarkSignals(
        from evidence: NextStateEvidence,
        input: PreferenceSignalExtractionInput
    ) -> [PreferenceSignal] {
        var signals: [PreferenceSignal] = []
        let evaluativeDecision = mappedEvaluativeDecision(from: evidence)
        let polarity = mappedPolarity(from: evidence)

        if evidence.evaluativeCandidate != nil {
            signals.append(
                makeSignal(
                    type: .outcome,
                    evidence: evidence,
                    input: input,
                    evaluativeDecision: evaluativeDecision,
                    polarity: polarity,
                    scope: taskFamilyScope(for: input),
                    hint: nil,
                    proposedAction: nil
                )
            )
        }

        if benchmarkRequiresTeacherConfirmation(evidence) || evidence.guiFailureBucket == .riskBlocked {
            let isPositiveRiskGuard = evaluativeDecision == .pass && benchmarkRequiresTeacherConfirmation(evidence)
            signals.append(
                makeSignal(
                    type: .risk,
                    evidence: evidence,
                    input: input,
                    evaluativeDecision: isPositiveRiskGuard ? .pass : .fail,
                    polarity: isPositiveRiskGuard ? .reinforce : .discourage,
                    scope: taskFamilyScope(for: input),
                    hint: "Keep teacher confirmation enabled for similar high-risk steps.",
                    proposedAction: "require_teacher_confirmation"
                )
            )
        }

        return signals
    }

    private static func extractSafetyBlockSignals(
        from evidence: NextStateEvidence,
        input: PreferenceSignalExtractionInput
    ) -> [PreferenceSignal] {
        guard isSafetyBlocked(evidence) else {
            return []
        }

        return [
            makeSignal(
                type: .risk,
                evidence: evidence,
                input: input,
                evaluativeDecision: .fail,
                polarity: .discourage,
                scope: appScope(for: input.turn),
                hint: "Similar steps should stay blocked or require teacher confirmation.",
                proposedAction: "require_teacher_confirmation"
            )
        ]
    }

    private static func makeSignal(
        type: PreferenceSignalType,
        evidence: NextStateEvidence,
        input: PreferenceSignalExtractionInput,
        evaluativeDecision: PreferenceSignalEvaluativeDecision,
        polarity: PreferenceSignalPolarity,
        scope: PreferenceSignalScopeReference,
        hint: String?,
        proposedAction: String?
    ) -> PreferenceSignal {
        let timestamp = input.extractedAt ?? evidence.timestamp

        return PreferenceSignal(
            signalId: derivedSignalId(type: type, evidence: evidence),
            turnId: input.turn.turnId,
            traceId: input.turn.traceId,
            sessionId: input.turn.sessionId,
            taskId: input.turn.taskId,
            stepId: input.turn.stepId,
            type: type,
            evaluativeDecision: evaluativeDecision,
            polarity: polarity,
            scope: scope,
            hint: normalizedOptionalString(hint),
            confidence: evidence.confidence,
            evidenceIds: [evidence.evidenceId],
            proposedAction: normalizedOptionalString(proposedAction),
            promotionStatus: .candidate,
            timestamp: timestamp
        )
    }

    private static func teacherReviewAction(for evidence: NextStateEvidence) -> TeacherQuickFeedbackAction? {
        if let decision = evidence.evaluativeCandidate?.decision,
           let action = TeacherQuickFeedbackAction(rawValue: decision) {
            return action
        }

        if let directive = evidence.directiveCandidate {
            if containsToken(directive.repairActionType, token: "locator")
                || containsToken(directive.action, token: "locator")
                || evidence.guiFailureBucket == .locatorResolutionFailed {
                return .fixLocator
            }
            if containsToken(directive.repairActionType, token: "reteach")
                || containsToken(directive.action, token: "reteach") {
                return .reteach
            }
        }

        if evidence.guiFailureBucket == .riskBlocked {
            return .tooDangerous
        }

        return nil
    }

    private static func mappedEvaluativeDecision(
        from evidence: NextStateEvidence
    ) -> PreferenceSignalEvaluativeDecision {
        switch evidence.evaluativeCandidate?.polarity {
        case .positive:
            return .pass
        case .negative:
            return .fail
        case .neutral:
            return .neutral
        case .none:
            return .neutral
        }
    }

    private static func mappedPolarity(
        from evidence: NextStateEvidence
    ) -> PreferenceSignalPolarity {
        switch evidence.evaluativeCandidate?.polarity {
        case .positive:
            return .reinforce
        case .negative:
            return .discourage
        case .neutral:
            return .neutral
        case .none:
            return .neutral
        }
    }

    private static func taskFamilyScope(
        for input: PreferenceSignalExtractionInput
    ) -> PreferenceSignalScopeReference {
        PreferenceSignalScopeReference.taskFamily(
            input.taskFamily ?? defaultTaskFamily(for: input.turn)
        )
    }

    private static func appScope(
        for turn: InteractionTurn
    ) -> PreferenceSignalScopeReference {
        .app(bundleId: turn.appContext.appBundleId, appName: turn.appContext.appName)
    }

    private static func defaultTaskFamily(for turn: InteractionTurn) -> String {
        "\(turn.mode.rawValue).\(turn.turnKind.rawValue)"
    }

    private static func defaultRepairAction(for action: TeacherQuickFeedbackAction) -> String {
        switch action {
        case .fixLocator:
            return "updateSkillLocator"
        case .reteach:
            return "reteach_step"
        case .approved, .rejected, .needsRevision, .tooDangerous, .wrongOrder, .wrongStyle:
            return "repair_step"
        }
    }

    private static func benchmarkRequiresTeacherConfirmation(_ evidence: NextStateEvidence) -> Bool {
        if containsToken(evidence.summary, token: "needs_teacher_confirmation")
            || containsToken(evidence.summary, token: "teacher confirmation")
            || containsToken(evidence.summary, token: "confirmation-gated") {
            return true
        }

        return evidence.rawRefs.contains { rawRef in
            containsToken(rawRef.note, token: "needs_teacher_confirmation")
                || containsToken(rawRef.note, token: "teacher confirmation")
                || containsToken(rawRef.note, token: "confirmation-gated")
        }
    }

    private static func isSafetyBlocked(_ evidence: NextStateEvidence) -> Bool {
        if evidence.guiFailureBucket == .riskBlocked {
            return true
        }

        if evidence.source != .executionRuntime {
            return false
        }

        if containsToken(evidence.summary, token: "blocked by a safety rule")
            || containsToken(evidence.summary, token: "blocked")
            || containsToken(evidence.evaluativeCandidate?.decision, token: "blocked") {
            return true
        }

        return evidence.rawRefs.contains { rawRef in
            containsToken(rawRef.note, token: "blocked")
                || containsToken(rawRef.identifier, token: "blocked")
        }
    }

    private static func indicatesLocatorIssue(_ evidence: NextStateEvidence) -> Bool {
        if evidence.guiFailureBucket == .locatorResolutionFailed {
            return true
        }

        if containsToken(evidence.summary, token: "locator")
            || containsToken(evidence.summary, token: "coordinate fallback")
            || containsToken(evidence.summary, token: "text anchor")
            || containsToken(evidence.evaluativeCandidate?.rationale, token: "locator")
            || containsToken(evidence.evaluativeCandidate?.rationale, token: "coordinate")
            || containsToken(evidence.evaluativeCandidate?.rationale, token: "anchor") {
            return true
        }

        if let directive = evidence.directiveCandidate {
            return containsToken(directive.action, token: "locator")
                || containsToken(directive.repairActionType, token: "locator")
                || containsToken(directive.repairActionType, token: "relocalize")
                || containsToken(directive.hint, token: "locator")
                || containsToken(directive.hint, token: "text anchor")
                || containsToken(directive.hint, token: "coordinate")
        }

        return false
    }

    private static func bestHint(for evidence: NextStateEvidence) -> String? {
        if let directiveHint = normalizedOptionalString(evidence.directiveCandidate?.hint) {
            return directiveHint
        }

        let rawNote = evidence.rawRefs
            .compactMap(\.note)
            .first { normalizedOptionalString($0) != nil }

        return normalizedOptionalString(rawNote) ?? normalizedOptionalString(evidence.summary)
    }

    private static func derivedSignalId(
        type: PreferenceSignalType,
        evidence: NextStateEvidence
    ) -> String {
        "signal-\(type.rawValue)-\(sanitizedToken(evidence.evidenceId))"
    }

    private static func dateKey(from timestamp: String) -> String {
        guard timestamp.count >= 10 else {
            return "unknown-date"
        }
        return String(timestamp.prefix(10))
    }

    private static func normalizedOptionalString(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func containsToken(_ value: String?, token: String) -> Bool {
        guard let value else {
            return false
        }
        return value.localizedCaseInsensitiveContains(token)
    }

    private static func sanitizedToken(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let token = String(scalars)
        return token.isEmpty ? "signal" : token
    }
}
