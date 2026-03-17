import Foundation

enum TeacherQuickFeedbackModifier: String, Codable, Equatable, Sendable {
    case command
    case shift
    case option
    case control

    var displayToken: String {
        switch self {
        case .command:
            return "Cmd"
        case .shift:
            return "Shift"
        case .option:
            return "Option"
        case .control:
            return "Control"
        }
    }
}

struct TeacherQuickFeedbackShortcut: Codable, Equatable, Sendable {
    let key: String
    let modifiers: [TeacherQuickFeedbackModifier]

    var identifier: String {
        let modifierToken = modifiers.map(\.rawValue).joined(separator: "+")
        return modifierToken.isEmpty ? key : "\(modifierToken)+\(key)"
    }

    var displayLabel: String {
        let modifierLabels = modifiers.map(\.displayToken)
        if modifierLabels.isEmpty {
            return key.uppercased()
        }
        return "\(modifierLabels.joined(separator: "+"))+\(key.uppercased())"
    }
}

enum TeacherReviewEvidenceType: String, Codable, Equatable, Sendable {
    case evaluative
    case directive
}

enum TeacherReviewEvidenceCategory: String, Codable, Equatable, Sendable {
    case resultQuality
    case locatorRepair
    case reteach
    case safetyRisk
    case executionOrder
    case executionStyle
    case revisionRequest
}

enum TeacherReviewEvidencePolarity: String, Codable, Equatable, Sendable {
    case positive
    case negative
}

struct TeacherReviewEvidence: Codable, Equatable, Sendable {
    let schemaVersion: String
    let source: String
    let action: TeacherQuickFeedbackAction
    let evidenceType: TeacherReviewEvidenceType
    let category: TeacherReviewEvidenceCategory
    let polarity: TeacherReviewEvidencePolarity
    let summary: String
    let note: String?
    let shortcut: TeacherQuickFeedbackShortcut
    let shortcutId: String
    let repairActionType: String?

    init(
        action: TeacherQuickFeedbackAction,
        note: String?,
        repairActionType: String? = nil
    ) {
        self.schemaVersion = "teacher.review.evidence.v0"
        self.source = "teacherReview"
        self.action = action
        self.evidenceType = action.evidenceType
        self.category = action.evidenceCategory
        self.polarity = action.polarity
        self.summary = action.summaryText
        self.note = note
        self.shortcut = action.shortcut
        self.shortcutId = "teacher.quick-feedback.\(action.rawValue)"
        self.repairActionType = repairActionType
    }
}

enum TeacherQuickFeedbackAction: String, Codable, Identifiable, CaseIterable, Sendable {
    case approved
    case rejected
    case needsRevision
    case fixLocator
    case reteach
    case tooDangerous
    case wrongOrder
    case wrongStyle

    static let quickActions: [TeacherQuickFeedbackAction] = [
        .approved,
        .rejected,
        .fixLocator,
        .reteach,
        .tooDangerous,
        .wrongOrder,
        .wrongStyle
    ]

    static let allCases: [TeacherQuickFeedbackAction] = quickActions + [.needsRevision]

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .approved:
            return "通过"
        case .rejected:
            return "驳回"
        case .needsRevision:
            return "修正"
        case .fixLocator:
            return "修 locator"
        case .reteach:
            return "重示教"
        case .tooDangerous:
            return "太危险"
        case .wrongOrder:
            return "顺序不对"
        case .wrongStyle:
            return "风格不对"
        }
    }

    var hintText: String {
        switch self {
        case .approved:
            return "结果可接受，记录正向老师审阅信号。"
        case .rejected:
            return "结果不可接受，但暂不直接指定修复路径。"
        case .needsRevision:
            return "旧版补充型反馈，建议改用更明确的 quick action。"
        case .fixLocator:
            return "优先把失败归因为 locator 问题，并写入修复动作。"
        case .reteach:
            return "优先要求重新示教当前步骤，并写入修复动作。"
        case .tooDangerous:
            return "把本次执行标记为风险过高。"
        case .wrongOrder:
            return "指出动作顺序不符合老师习惯或任务要求。"
        case .wrongStyle:
            return "指出动作风格、话术或操作习惯不符合老师偏好。"
        }
    }

    var summaryText: String {
        switch self {
        case .approved:
            return "老师判定本次执行可接受。"
        case .rejected:
            return "老师判定本次执行不可接受。"
        case .needsRevision:
            return "老师要求继续修正当前执行结果。"
        case .fixLocator:
            return "老师要求优先修正 locator。"
        case .reteach:
            return "老师要求重新示教当前步骤。"
        case .tooDangerous:
            return "老师判定本次执行过于危险。"
        case .wrongOrder:
            return "老师指出本次执行的步骤顺序不对。"
        case .wrongStyle:
            return "老师指出本次执行的操作风格不对。"
        }
    }

    var evidenceType: TeacherReviewEvidenceType {
        switch self {
        case .fixLocator, .reteach:
            return .directive
        case .approved, .rejected, .needsRevision, .tooDangerous, .wrongOrder, .wrongStyle:
            return .evaluative
        }
    }

    var evidenceCategory: TeacherReviewEvidenceCategory {
        switch self {
        case .approved, .rejected:
            return .resultQuality
        case .needsRevision:
            return .revisionRequest
        case .fixLocator:
            return .locatorRepair
        case .reteach:
            return .reteach
        case .tooDangerous:
            return .safetyRisk
        case .wrongOrder:
            return .executionOrder
        case .wrongStyle:
            return .executionStyle
        }
    }

    var polarity: TeacherReviewEvidencePolarity {
        switch self {
        case .approved:
            return .positive
        case .rejected, .needsRevision, .fixLocator, .reteach, .tooDangerous, .wrongOrder, .wrongStyle:
            return .negative
        }
    }

    var shortcut: TeacherQuickFeedbackShortcut {
        switch self {
        case .approved:
            return TeacherQuickFeedbackShortcut(key: "1", modifiers: [.command])
        case .rejected:
            return TeacherQuickFeedbackShortcut(key: "2", modifiers: [.command])
        case .fixLocator:
            return TeacherQuickFeedbackShortcut(key: "3", modifiers: [.command])
        case .reteach:
            return TeacherQuickFeedbackShortcut(key: "4", modifiers: [.command])
        case .tooDangerous:
            return TeacherQuickFeedbackShortcut(key: "5", modifiers: [.command])
        case .wrongOrder:
            return TeacherQuickFeedbackShortcut(key: "6", modifiers: [.command])
        case .wrongStyle:
            return TeacherQuickFeedbackShortcut(key: "7", modifiers: [.command])
        case .needsRevision:
            return TeacherQuickFeedbackShortcut(key: "8", modifiers: [.command])
        }
    }

    func makeTeacherReviewEvidence(
        note: String?,
        repairActionType: String? = nil
    ) -> TeacherReviewEvidence {
        TeacherReviewEvidence(
            action: self,
            note: note,
            repairActionType: repairActionType
        )
    }
}

typealias TeacherFeedbackDecision = TeacherQuickFeedbackAction
