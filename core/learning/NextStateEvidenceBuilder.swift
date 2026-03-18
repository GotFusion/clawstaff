import Foundation

public struct NextStateEvidenceBuildInput: Equatable, Sendable {
    public let evidenceId: String?
    public let turnContext: NextStateEvidenceTurnContext
    public let source: NextStateEvidenceSource
    public let summary: String
    public let rawRefs: [NextStateEvidenceRawReference]
    public let timestamp: String
    public let confidence: Double?
    public let severity: NextStateEvidenceSeverity?
    public let role: NextStateEvidenceRole?
    public let guiFailureBucket: NextStateEvidenceGUIFailureBucket?
    public let evaluativeCandidate: NextStateEvaluativeCandidate?
    public let directiveCandidate: NextStateDirectiveCandidate?
    public let decisionHint: String?
    public let statusHint: String?
    public let errorCodeHint: String?

    public init(
        evidenceId: String? = nil,
        turnContext: NextStateEvidenceTurnContext,
        source: NextStateEvidenceSource,
        summary: String,
        rawRefs: [NextStateEvidenceRawReference],
        timestamp: String,
        confidence: Double? = nil,
        severity: NextStateEvidenceSeverity? = nil,
        role: NextStateEvidenceRole? = nil,
        guiFailureBucket: NextStateEvidenceGUIFailureBucket? = nil,
        evaluativeCandidate: NextStateEvaluativeCandidate? = nil,
        directiveCandidate: NextStateDirectiveCandidate? = nil,
        decisionHint: String? = nil,
        statusHint: String? = nil,
        errorCodeHint: String? = nil
    ) {
        self.evidenceId = evidenceId
        self.turnContext = turnContext
        self.source = source
        self.summary = summary
        self.rawRefs = rawRefs
        self.timestamp = timestamp
        self.confidence = confidence
        self.severity = severity
        self.role = role
        self.guiFailureBucket = guiFailureBucket
        self.evaluativeCandidate = evaluativeCandidate
        self.directiveCandidate = directiveCandidate
        self.decisionHint = decisionHint
        self.statusHint = statusHint
        self.errorCodeHint = errorCodeHint
    }
}

public enum NextStateEvidenceBuilder {
    public static func build(_ input: NextStateEvidenceBuildInput) -> NextStateEvidence {
        let evidenceId = input.evidenceId ?? derivedEvidenceId(for: input)
        let guiFailureBucket = input.guiFailureBucket ?? deriveGUIFailureBucket(for: input)
        let role = input.role ?? deriveRole(for: input)
        let severity = input.severity ?? deriveSeverity(for: input, guiFailureBucket: guiFailureBucket)
        let confidence = normalizedConfidence(input.confidence ?? defaultConfidence(for: input.source))

        return NextStateEvidence(
            evidenceId: evidenceId,
            turnId: input.turnContext.turnId,
            traceId: input.turnContext.traceId,
            sessionId: input.turnContext.sessionId,
            taskId: input.turnContext.taskId,
            stepId: input.turnContext.stepId,
            source: input.source,
            summary: input.summary,
            rawRefs: input.rawRefs,
            timestamp: input.timestamp,
            confidence: confidence,
            severity: severity,
            role: role,
            guiFailureBucket: guiFailureBucket,
            evaluativeCandidate: input.evaluativeCandidate,
            directiveCandidate: input.directiveCandidate
        )
    }

    public static func derivedEvidenceId(for input: NextStateEvidenceBuildInput) -> String {
        let timestampToken = sanitizedToken(input.timestamp)
        return "evidence-\(input.source.rawValue)-\(sanitizedToken(input.turnContext.turnId))-\(timestampToken)"
    }

    public static func evidenceFileURL(
        for evidence: NextStateEvidence,
        evidenceRootDirectory: URL
    ) -> URL {
        let dateDirectory = dateKey(from: evidence.timestamp)
        return evidenceRootDirectory
            .appendingPathComponent(dateDirectory, isDirectory: true)
            .appendingPathComponent(evidence.sessionId, isDirectory: true)
            .appendingPathComponent("\(evidence.turnId).jsonl", isDirectory: false)
    }

    @discardableResult
    public static func append(
        _ evidence: NextStateEvidence,
        evidenceRootDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let fileURL = evidenceFileURL(for: evidence, evidenceRootDirectory: evidenceRootDirectory)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var payload = try encoder.encode(evidence)
        payload.append(0x0A)

        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
            try handle.close()
        } else {
            try payload.write(to: fileURL, options: .atomic)
        }

        return fileURL
    }

    @discardableResult
    public static func append(
        _ evidence: [NextStateEvidence],
        evidenceRootDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        try evidence.map {
            try append($0, evidenceRootDirectory: evidenceRootDirectory, fileManager: fileManager)
        }
    }

    public static func deriveRole(for input: NextStateEvidenceBuildInput) -> NextStateEvidenceRole {
        if input.evaluativeCandidate != nil, input.directiveCandidate != nil {
            return .mixed
        }
        if input.directiveCandidate != nil {
            return .directive
        }
        if input.evaluativeCandidate != nil {
            return .evaluative
        }

        switch input.source {
        case .chatgptSuggestion:
            return .directive
        case .teacherReview, .executionRuntime, .replayVerify, .driftDetection, .benchmarkResult:
            return .evaluative
        }
    }

    public static func deriveSeverity(
        for input: NextStateEvidenceBuildInput,
        guiFailureBucket: NextStateEvidenceGUIFailureBucket?
    ) -> NextStateEvidenceSeverity {
        if input.decisionHint == TeacherQuickFeedbackAction.tooDangerous.rawValue
            || guiFailureBucket == .riskBlocked
            || containsToken(input.statusHint, token: "blocked")
            || containsToken(input.errorCodeHint, token: "blocked")
            || containsToken(input.errorCodeHint, token: "risk") {
            return .critical
        }

        if let evaluativeCandidate = input.evaluativeCandidate {
            switch evaluativeCandidate.polarity {
            case .positive:
                return .info
            case .neutral:
                return .warning
            case .negative:
                return input.directiveCandidate == nil ? .error : .warning
            }
        }

        if guiFailureBucket != nil
            || containsToken(input.statusHint, token: "failed")
            || containsToken(input.errorCodeHint, token: "failed") {
            return .error
        }

        if input.directiveCandidate != nil {
            return .warning
        }

        return .info
    }

    public static func deriveGUIFailureBucket(
        for input: NextStateEvidenceBuildInput
    ) -> NextStateEvidenceGUIFailureBucket? {
        if input.decisionHint == TeacherQuickFeedbackAction.fixLocator.rawValue {
            return .locatorResolutionFailed
        }
        if input.decisionHint == TeacherQuickFeedbackAction.tooDangerous.rawValue {
            return .riskBlocked
        }

        if containsToken(input.errorCodeHint, token: "locator")
            || containsToken(input.errorCodeHint, token: "target")
            || containsToken(input.errorCodeHint, token: "missing-locator")
            || containsToken(input.summary, token: "locator") {
            return .locatorResolutionFailed
        }

        if containsToken(input.errorCodeHint, token: "action-kind")
            || containsToken(input.errorCodeHint, token: "action_kind")
            || containsToken(input.errorCodeHint, token: "kind-mismatch")
            || containsToken(input.summary, token: "action kind") {
            return .actionKindMismatch
        }

        if containsToken(input.statusHint, token: "blocked")
            || containsToken(input.errorCodeHint, token: "blocked")
            || containsToken(input.errorCodeHint, token: "risk")
            || containsToken(input.summary, token: "danger") {
            return .riskBlocked
        }

        return nil
    }

    public static func defaultConfidence(for source: NextStateEvidenceSource) -> Double {
        switch source {
        case .teacherReview:
            return 1.0
        case .benchmarkResult:
            return 0.95
        case .executionRuntime:
            return 0.9
        case .replayVerify:
            return 0.88
        case .driftDetection:
            return 0.82
        case .chatgptSuggestion:
            return 0.66
        }
    }

    private static func normalizedConfidence(_ confidence: Double) -> Double {
        min(max(confidence, 0.0), 1.0)
    }

    private static func containsToken(_ value: String?, token: String) -> Bool {
        guard let value else {
            return false
        }
        return value.lowercased().contains(token.lowercased())
    }

    private static func sanitizedToken(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let token = String(scalars)
        return token.isEmpty ? "evidence" : token
    }

    private static func dateKey(from timestamp: String) -> String {
        guard timestamp.count >= 10 else {
            return "unknown-date"
        }
        return String(timestamp.prefix(10))
    }
}
