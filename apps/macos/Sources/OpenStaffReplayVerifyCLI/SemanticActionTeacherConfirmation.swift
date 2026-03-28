import Foundation

enum SemanticActionTeacherConfirmationStatus: String, Codable {
    case required = "required"
    case approved = "approved"
}

struct SemanticActionTeacherConfirmationPolicy: Codable {
    let minimumConfidence: Double
    let requireManualReviewActions: Bool
    let requireForSwitchApp: Bool
    let requireForDrag: Bool
    let requireForBulkType: Bool
    let bulkTypeMinimumLength: Int

    static let `default` = SemanticActionTeacherConfirmationPolicy(
        minimumConfidence: 0.86,
        requireManualReviewActions: true,
        requireForSwitchApp: true,
        requireForDrag: true,
        requireForBulkType: true,
        bulkTypeMinimumLength: 20
    )

    func merged(overrides: SemanticActionTeacherConfirmationPolicyOverrides?) -> SemanticActionTeacherConfirmationPolicy {
        guard let overrides else {
            return self
        }
        return SemanticActionTeacherConfirmationPolicy(
            minimumConfidence: overrides.minimumConfidence ?? minimumConfidence,
            requireManualReviewActions: overrides.requireManualReviewActions ?? requireManualReviewActions,
            requireForSwitchApp: overrides.requireForSwitchApp ?? requireForSwitchApp,
            requireForDrag: overrides.requireForDrag ?? requireForDrag,
            requireForBulkType: overrides.requireForBulkType ?? requireForBulkType,
            bulkTypeMinimumLength: overrides.bulkTypeMinimumLength ?? bulkTypeMinimumLength
        )
    }
}

struct SemanticActionTeacherConfirmationPolicyOverrides: Codable {
    let minimumConfidence: Double?
    let requireManualReviewActions: Bool?
    let requireForSwitchApp: Bool?
    let requireForDrag: Bool?
    let requireForBulkType: Bool?
    let bulkTypeMinimumLength: Int?
}

struct SemanticActionTeacherConfirmationPolicySummary: Codable {
    let minimumConfidence: Double
    let requireManualReviewActions: Bool
    let requireForSwitchApp: Bool
    let requireForDrag: Bool
    let requireForBulkType: Bool
    let bulkTypeMinimumLength: Int

    init(policy: SemanticActionTeacherConfirmationPolicy) {
        self.minimumConfidence = policy.minimumConfidence
        self.requireManualReviewActions = policy.requireManualReviewActions
        self.requireForSwitchApp = policy.requireForSwitchApp
        self.requireForDrag = policy.requireForDrag
        self.requireForBulkType = policy.requireForBulkType
        self.bulkTypeMinimumLength = policy.bulkTypeMinimumLength
    }
}

struct SemanticActionTeacherConfirmationReason: Codable {
    let code: String
    let message: String
}

struct SemanticActionTeacherConfirmationSelectorCandidate: Codable {
    let targetRole: String
    let locatorType: String?
    let selectorStrategy: String?
    let confidence: Double?
    let isPreferred: Bool
    let elementRole: String?
    let elementTitle: String?
    let elementIdentifier: String?
}

struct SemanticActionTeacherConfirmationAssertionSummary: Codable {
    let assertionType: String
    let isRequired: Bool
    let payload: [String: String]
}

struct SemanticActionTeacherConfirmationReview: Codable {
    let status: SemanticActionTeacherConfirmationStatus
    let teacherConfirmed: Bool
    let generatedAt: String
    let actionConfidence: Double?
    let policy: SemanticActionTeacherConfirmationPolicySummary
    let reasons: [SemanticActionTeacherConfirmationReason]
    let selectorCandidates: [SemanticActionTeacherConfirmationSelectorCandidate]
    let assertions: [SemanticActionTeacherConfirmationAssertionSummary]
    let expectedContext: [String: String]
    let actualContext: [String: String]
}

struct SemanticActionTeacherConfirmationArtifact: Codable {
    let schemaVersion: String
    let actionId: String
    let sessionId: String
    let taskId: String?
    let traceId: String?
    let stepId: String?
    let actionType: String
    let dryRun: Bool
    let executionStatus: String
    let summary: String
    let errorCode: String?
    let executedAt: String
    let teacherConfirmation: SemanticActionTeacherConfirmationReview
}

final class SemanticActionTeacherConfirmationArtifactStore {
    private let rootURL: URL
    private let fileManager = FileManager.default

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func store(
        action: SemanticActionStoreAction,
        report: SemanticActionExecutionReport
    ) throws -> URL? {
        guard let teacherConfirmation = report.teacherConfirmation else {
            return nil
        }

        let dateComponent = String(report.executedAt.prefix(10))
        let sessionDirectory = rootURL
            .appendingPathComponent(dateComponent, isDirectory: true)
            .appendingPathComponent(sanitizePathComponent(action.sessionId), isDirectory: true)
        try fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)

        let filename = "\(sanitizePathComponent(action.actionId))--\(teacherConfirmation.status.rawValue).json"
        let artifactURL = sessionDirectory.appendingPathComponent(filename, isDirectory: false)
        let artifact = SemanticActionTeacherConfirmationArtifact(
            schemaVersion: "openstaff.semantic-action-teacher-confirmation.v0",
            actionId: action.actionId,
            sessionId: action.sessionId,
            taskId: action.taskId,
            traceId: action.traceId,
            stepId: action.stepId,
            actionType: action.actionType,
            dryRun: report.dryRun,
            executionStatus: report.status.rawValue,
            summary: report.summary,
            errorCode: report.errorCode,
            executedAt: report.executedAt,
            teacherConfirmation: teacherConfirmation
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(artifact)
        try data.write(to: artifactURL, options: .atomic)
        return artifactURL
    }

    private func sanitizePathComponent(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.components(separatedBy: invalid).filter { !$0.isEmpty }
        return components.isEmpty ? "unknown" : components.joined(separator: "-")
    }
}
