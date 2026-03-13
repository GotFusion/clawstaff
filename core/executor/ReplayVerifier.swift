import Foundation

public enum ReplayStepVerificationStatus: String, Codable {
    case resolved
    case degraded
    case failed
    case skipped
}

public struct ReplayFailureStat: Codable, Equatable {
    public let reason: SemanticTargetFailureReason
    public let count: Int

    public init(reason: SemanticTargetFailureReason, count: Int) {
        self.reason = reason
        self.count = count
    }
}

public struct ReplayStepVerification: Codable, Equatable {
    public let stepId: String
    public let instruction: String
    public let sourceEventIds: [String]
    public let status: ReplayStepVerificationStatus
    public let matchedLocatorType: SemanticLocatorType?
    public let failureReason: SemanticTargetFailureReason?
    public let message: String
    public let matchedElement: ReplayElementSnapshot?
    public let attempts: [SemanticTargetResolutionAttempt]

    public init(
        stepId: String,
        instruction: String,
        sourceEventIds: [String],
        status: ReplayStepVerificationStatus,
        matchedLocatorType: SemanticLocatorType? = nil,
        failureReason: SemanticTargetFailureReason? = nil,
        message: String,
        matchedElement: ReplayElementSnapshot? = nil,
        attempts: [SemanticTargetResolutionAttempt] = []
    ) {
        self.stepId = stepId
        self.instruction = instruction
        self.sourceEventIds = sourceEventIds
        self.status = status
        self.matchedLocatorType = matchedLocatorType
        self.failureReason = failureReason
        self.message = message
        self.matchedElement = matchedElement
        self.attempts = attempts
    }
}

public struct ReplayVerificationSummary: Codable, Equatable {
    public let totalSteps: Int
    public let checkedSteps: Int
    public let skippedSteps: Int
    public let resolvedSteps: Int
    public let degradedSteps: Int
    public let failedSteps: Int
    public let failureStats: [ReplayFailureStat]

    public init(
        totalSteps: Int,
        checkedSteps: Int,
        skippedSteps: Int,
        resolvedSteps: Int,
        degradedSteps: Int,
        failedSteps: Int,
        failureStats: [ReplayFailureStat]
    ) {
        self.totalSteps = totalSteps
        self.checkedSteps = checkedSteps
        self.skippedSteps = skippedSteps
        self.resolvedSteps = resolvedSteps
        self.degradedSteps = degradedSteps
        self.failedSteps = failedSteps
        self.failureStats = failureStats
    }
}

public struct ReplayVerificationReport: Codable, Equatable {
    public let knowledgeItemId: String
    public let taskId: String
    public let sessionId: String
    public let verifiedAt: String
    public let snapshot: ReplayEnvironmentSnapshot
    public let steps: [ReplayStepVerification]
    public let summary: ReplayVerificationSummary

    public init(
        knowledgeItemId: String,
        taskId: String,
        sessionId: String,
        verifiedAt: String,
        snapshot: ReplayEnvironmentSnapshot,
        steps: [ReplayStepVerification],
        summary: ReplayVerificationSummary
    ) {
        self.knowledgeItemId = knowledgeItemId
        self.taskId = taskId
        self.sessionId = sessionId
        self.verifiedAt = verifiedAt
        self.snapshot = snapshot
        self.steps = steps
        self.summary = summary
    }
}

public struct ReplayVerifier {
    private let snapshotProvider: any ReplayEnvironmentSnapshotProviding
    private let resolver: SemanticTargetResolver
    private let nowProvider: () -> Date
    private let timestampFormatter: ISO8601DateFormatter

    public init(
        snapshotProvider: any ReplayEnvironmentSnapshotProviding = LiveReplayEnvironmentSnapshotProvider(),
        resolver: SemanticTargetResolver = SemanticTargetResolver(),
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.snapshotProvider = snapshotProvider
        self.resolver = resolver
        self.nowProvider = nowProvider

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestampFormatter = formatter
    }

    public func verify(item: KnowledgeItem) -> ReplayVerificationReport {
        verify(item: item, snapshot: snapshotProvider.snapshot())
    }

    public func verify(
        item: KnowledgeItem,
        snapshot: ReplayEnvironmentSnapshot
    ) -> ReplayVerificationReport {
        let steps = item.steps.map {
            verify(
                step: $0,
                context: item.context,
                snapshot: snapshot
            )
        }
        let summary = buildSummary(steps: steps)

        return ReplayVerificationReport(
            knowledgeItemId: item.knowledgeItemId,
            taskId: item.taskId,
            sessionId: item.sessionId,
            verifiedAt: timestampFormatter.string(from: nowProvider()),
            snapshot: snapshot,
            steps: steps,
            summary: summary
        )
    }

    public func verify(
        step: KnowledgeStep,
        context: KnowledgeContext,
        snapshot: ReplayEnvironmentSnapshot
    ) -> ReplayStepVerification {
        guard let target = step.target else {
            return ReplayStepVerification(
                stepId: step.stepId,
                instruction: step.instruction,
                sourceEventIds: step.sourceEventIds,
                status: .skipped,
                message: "该步骤不包含可定位目标，已跳过 dry-run 验证。"
            )
        }

        let semanticTargets = normalizedTargets(from: target, context: context)
        let resolution = resolver.resolve(
            targets: semanticTargets,
            preferredLocatorType: target.preferredLocatorType,
            coordinate: target.coordinate,
            in: snapshot
        )

        let status: ReplayStepVerificationStatus
        switch resolution.status {
        case .resolved:
            status = .resolved
        case .degraded:
            status = .degraded
        case .unresolved:
            status = .failed
        }

        return ReplayStepVerification(
            stepId: step.stepId,
            instruction: step.instruction,
            sourceEventIds: step.sourceEventIds,
            status: status,
            matchedLocatorType: resolution.matchedLocatorType,
            failureReason: resolution.failureReason,
            message: resolution.message,
            matchedElement: resolution.matchedElement,
            attempts: resolution.attempts
        )
    }

    private func normalizedTargets(
        from target: KnowledgeStepTarget,
        context: KnowledgeContext
    ) -> [SemanticTarget] {
        guard !target.semanticTargets.isEmpty else {
            guard let coordinate = target.coordinate else {
                return []
            }

            return [
                SemanticTarget.coordinateFallback(
                    appBundleId: context.appBundleId,
                    windowTitle: context.windowTitle,
                    coordinate: coordinate,
                    source: .inferred
                )
            ]
        }

        return target.semanticTargets
    }

    private func buildSummary(steps: [ReplayStepVerification]) -> ReplayVerificationSummary {
        let checkedSteps = steps.filter { $0.status != .skipped }
        let skippedSteps = steps.count - checkedSteps.count
        let resolvedSteps = checkedSteps.filter { $0.status == .resolved }.count
        let degradedSteps = checkedSteps.filter { $0.status == .degraded }.count
        let failedSteps = checkedSteps.filter { $0.status == .failed }.count

        var counters: [SemanticTargetFailureReason: Int] = [:]
        for step in checkedSteps {
            guard let failureReason = step.failureReason else {
                continue
            }
            counters[failureReason, default: 0] += 1
        }

        let failureStats = counters
            .map { ReplayFailureStat(reason: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.reason.rawValue < rhs.reason.rawValue
                }
                return lhs.count > rhs.count
            }

        return ReplayVerificationSummary(
            totalSteps: steps.count,
            checkedSteps: checkedSteps.count,
            skippedSteps: skippedSteps,
            resolvedSteps: resolvedSteps,
            degradedSteps: degradedSteps,
            failedSteps: failedSteps,
            failureStats: failureStats
        )
    }
}
