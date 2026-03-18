import Foundation

public enum TurnLearningEligibilityStatus: String, Codable, CaseIterable, Sendable {
    case eligible
    case ineligible
    case needsReview = "needs_review"
}

public enum TurnLearningEligibilityReasonCode: String, Codable, CaseIterable, Sendable {
    case mainlineTaskProgression = "mainline_task_progression"
    case mainlineSkillExecution = "mainline_skill_execution"
    case mainlineRepair = "mainline_repair"
    case privacyExcluded = "privacy_excluded"
    case syntheticFixture = "synthetic_fixture"
    case assistPredictionOnly = "assist_prediction_only"
    case statusOnly = "status_only"
    case logOnly = "log_only"
    case backgroundOnly = "background_only"
    case insufficientTaskContext = "insufficient_task_context"
}

public struct TurnLearningEligibility: Codable, Equatable, Sendable {
    public let turnId: String
    public let traceId: String
    public let sessionId: String
    public let taskId: String
    public let stepId: String
    public let status: TurnLearningEligibilityStatus
    public let reasonCode: TurnLearningEligibilityReasonCode

    public var isEligible: Bool {
        status == .eligible
    }

    public init(
        turnId: String,
        traceId: String,
        sessionId: String,
        taskId: String,
        stepId: String,
        status: TurnLearningEligibilityStatus,
        reasonCode: TurnLearningEligibilityReasonCode
    ) {
        self.turnId = turnId
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.stepId = stepId
        self.status = status
        self.reasonCode = reasonCode
    }

    public static func classify(_ turn: InteractionTurn) -> TurnLearningEligibility {
        if hasSyntheticFixture(turn) {
            return decision(for: turn, status: .ineligible, reasonCode: .syntheticFixture)
        }

        if hasExclusionPrivacyTag(turn.privacyTags) {
            return decision(for: turn, status: .ineligible, reasonCode: .privacyExcluded)
        }

        if turn.turnKind == .repair {
            return decision(for: turn, status: .eligible, reasonCode: .mainlineRepair)
        }

        if turn.mode == .assist,
           turn.turnKind == .taskProgression,
           !hasAssistCommitEvidence(turn)
        {
            return decision(for: turn, status: .needsReview, reasonCode: .assistPredictionOnly)
        }

        if !hasMainlineTaskContext(turn) {
            if isLogOnly(turn) {
                return decision(for: turn, status: .ineligible, reasonCode: .logOnly)
            }
            if isStatusOnly(turn) {
                return decision(for: turn, status: .ineligible, reasonCode: .statusOnly)
            }
            if isBackgroundOnly(turn) {
                return decision(for: turn, status: .ineligible, reasonCode: .backgroundOnly)
            }
            return decision(for: turn, status: .needsReview, reasonCode: .insufficientTaskContext)
        }

        switch turn.turnKind {
        case .taskProgression:
            return decision(for: turn, status: .eligible, reasonCode: .mainlineTaskProgression)
        case .skillExecution:
            return decision(for: turn, status: .eligible, reasonCode: .mainlineSkillExecution)
        case .repair:
            return decision(for: turn, status: .eligible, reasonCode: .mainlineRepair)
        }
    }

    private static let actionArtifactKinds: Set<String> = [
        "casereport",
        "executionresult",
        "knowledgeitem",
        "raweventlog",
        "skillbundle",
        "sourcerecord",
        "taskchunk"
    ]

    private static let logArtifactKinds: Set<String> = [
        "benchmarkreview",
        "studentlog",
        "studentreview",
        "teacherfeedback"
    ]

    private static let actionKeywords = [
        "click",
        "confirm",
        "drag",
        "drop",
        "execute",
        "focus",
        "input",
        "merge",
        "open",
        "paste",
        "press",
        "run",
        "save",
        "select",
        "switch",
        "tap",
        "type",
        "关闭",
        "切换",
        "点击",
        "打开",
        "拖动",
        "执行",
        "按下",
        "搜索",
        "滚动",
        "确认",
        "粘贴",
        "聚焦",
        "输入",
        "运行",
        "选择"
    ]

    private static let statusKeywords = [
        "heartbeat",
        "mode stable",
        "mode transition",
        "notification",
        "progress update",
        "state only",
        "status",
        "transition",
        "同步状态",
        "提示",
        "播报",
        "显示",
        "状态",
        "说明",
        "通知",
        "进度"
    ]

    private static let logKeywords = [
        "diagnostic",
        "feedback",
        "log",
        "mirror",
        "report",
        "review",
        "summary",
        "trace",
        "反馈",
        "审阅",
        "总结",
        "报告",
        "回放",
        "日志",
        "诊断"
    ]

    private static let backgroundKeywords = [
        "analysis",
        "background",
        "benchmark",
        "drift",
        "index",
        "preflight",
        "research",
        "scan",
        "sync",
        "摘要",
        "分析",
        "后台",
        "扫描",
        "整理",
        "汇总",
        "索引",
        "资料",
        "预检"
    ]

    private static func decision(
        for turn: InteractionTurn,
        status: TurnLearningEligibilityStatus,
        reasonCode: TurnLearningEligibilityReasonCode
    ) -> TurnLearningEligibility {
        TurnLearningEligibility(
            turnId: turn.turnId,
            traceId: turn.traceId,
            sessionId: turn.sessionId,
            taskId: turn.taskId,
            stepId: turn.stepId,
            status: status,
            reasonCode: reasonCode
        )
    }

    private static func hasMainlineTaskContext(_ turn: InteractionTurn) -> Bool {
        hasStructuralTaskContext(turn) || textContainsAny(combinedText(for: turn), keywords: actionKeywords)
    }

    private static func hasStructuralTaskContext(_ turn: InteractionTurn) -> Bool {
        if turn.execution != nil || turn.semanticTargetSetRef != nil {
            return true
        }

        let observation = turn.observationRef
        if observation.rawEventLogPath != nil || observation.taskChunkPath != nil {
            return true
        }
        if !observation.eventIds.isEmpty
            || !observation.screenshotRefs.isEmpty
            || !observation.axRefs.isEmpty
            || !observation.ocrRefs.isEmpty
        {
            return true
        }

        let stepReference = turn.stepReference
        if !stepReference.sourceEventIds.isEmpty {
            return true
        }
        if hasValue(stepReference.knowledgeItemId)
            || hasValue(stepReference.knowledgeStepId)
            || hasValue(stepReference.skillStepId)
            || hasValue(stepReference.planStepId)
        {
            return true
        }

        let sourceKinds = normalizedArtifactKinds(turn.sourceRefs)
        return !sourceKinds.isDisjoint(with: actionArtifactKinds)
    }

    private static func hasAssistCommitEvidence(_ turn: InteractionTurn) -> Bool {
        if turn.execution != nil {
            return true
        }

        if let decision = turn.review?.decision, hasValue(decision) {
            return true
        }

        return turn.status != .captured
    }

    private static func hasSyntheticFixture(_ turn: InteractionTurn) -> Bool {
        if turn.sourceRefs.contains(where: { normalized($0.artifactKind) == "examplefixture" }) {
            return true
        }

        guard let note = turn.observationRef.note else {
            return false
        }

        let normalizedNote = normalized(note)
        return normalizedNote.contains("synthetic example") || normalizedNote.contains("example fixture")
    }

    private static func hasExclusionPrivacyTag(_ tags: [String]) -> Bool {
        tags.contains { tag in
            let normalizedTag = normalized(tag)
            return normalizedTag.contains("excluded")
                || normalizedTag.contains("sensitive")
                || normalizedTag.contains("redacted")
        }
    }

    private static func isLogOnly(_ turn: InteractionTurn) -> Bool {
        if hasStructuralTaskContext(turn) {
            return false
        }

        let sourceKinds = normalizedArtifactKinds(turn.sourceRefs)
        let hasOnlyLogArtifacts = !sourceKinds.isEmpty && sourceKinds.isSubset(of: logArtifactKinds)
        let text = combinedText(for: turn)
        return hasOnlyLogArtifacts || textContainsAny(text, keywords: logKeywords)
    }

    private static func isStatusOnly(_ turn: InteractionTurn) -> Bool {
        if hasStructuralTaskContext(turn) {
            return false
        }

        return textContainsAny(combinedText(for: turn), keywords: statusKeywords)
    }

    private static func isBackgroundOnly(_ turn: InteractionTurn) -> Bool {
        if hasStructuralTaskContext(turn) {
            return false
        }

        return textContainsAny(combinedText(for: turn), keywords: backgroundKeywords)
    }

    private static func normalizedArtifactKinds(_ sourceRefs: [InteractionTurnSourceReference]) -> Set<String> {
        Set(sourceRefs.map { normalized($0.artifactKind) })
    }

    private static func combinedText(for turn: InteractionTurn) -> String {
        [
            turn.intentSummary,
            turn.actionSummary,
            turn.stepReference.instruction,
            turn.review?.summary,
            turn.observationRef.note
        ]
        .compactMap { $0 }
        .map(normalized(_:))
        .joined(separator: " ")
    }

    private static func textContainsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains(normalized($0)) }
    }

    private static func hasValue(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
