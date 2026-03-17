import Foundation

public enum LearningActivityStatus: String, Codable, CaseIterable, Sendable {
    case on
    case paused
    case excluded
    case sensitiveMuted = "sensitive-muted"

    public var statusCode: String {
        rawValue
    }
}

public struct LearningSurfaceAppContext: Codable, Equatable, Sendable {
    public let appName: String
    public let appBundleId: String
    public let windowTitle: String?

    public init(
        appName: String,
        appBundleId: String,
        windowTitle: String? = nil
    ) {
        self.appName = appName
        self.appBundleId = appBundleId
        self.windowTitle = windowTitle
    }

    public static let unknown = LearningSurfaceAppContext(
        appName: "Unknown",
        appBundleId: "unknown.bundle.id",
        windowTitle: nil
    )
}

public struct LearningStatusRuleMatch: Codable, Equatable, Sendable {
    public let ruleId: String
    public let displayName: String

    public init(ruleId: String, displayName: String) {
        self.ruleId = ruleId
        self.displayName = displayName
    }
}

public struct LearningSessionStateInput: Equatable, Sendable {
    public let selectedMode: OpenStaffMode
    public let runningMode: OpenStaffMode?
    public let observesTeacherActions: Bool
    public let captureRunning: Bool
    public let teacherPaused: Bool
    public let currentApp: LearningSurfaceAppContext
    public let exclusionMatch: LearningStatusRuleMatch?
    public let sensitiveMatch: LearningStatusRuleMatch?
    public let lastSuccessfulWriteAt: Date?
    public let activeSessionId: String?
    public let capturedEventCount: Int
    public let updatedAt: Date

    public init(
        selectedMode: OpenStaffMode,
        runningMode: OpenStaffMode?,
        observesTeacherActions: Bool,
        captureRunning: Bool,
        teacherPaused: Bool,
        currentApp: LearningSurfaceAppContext,
        exclusionMatch: LearningStatusRuleMatch?,
        sensitiveMatch: LearningStatusRuleMatch?,
        lastSuccessfulWriteAt: Date?,
        activeSessionId: String?,
        capturedEventCount: Int,
        updatedAt: Date
    ) {
        self.selectedMode = selectedMode
        self.runningMode = runningMode
        self.observesTeacherActions = observesTeacherActions
        self.captureRunning = captureRunning
        self.teacherPaused = teacherPaused
        self.currentApp = currentApp
        self.exclusionMatch = exclusionMatch
        self.sensitiveMatch = sensitiveMatch
        self.lastSuccessfulWriteAt = lastSuccessfulWriteAt
        self.activeSessionId = activeSessionId
        self.capturedEventCount = capturedEventCount
        self.updatedAt = updatedAt
    }
}

public struct LearningSessionState: Codable, Equatable, Sendable {
    public let mode: OpenStaffMode
    public let runningMode: OpenStaffMode?
    public let observesTeacherActions: Bool
    public let captureRunning: Bool
    public let teacherPaused: Bool
    public let currentApp: LearningSurfaceAppContext
    public let status: LearningActivityStatus
    public let statusReason: String
    public let matchedRule: LearningStatusRuleMatch?
    public let lastSuccessfulWriteAt: Date?
    public let activeSessionId: String?
    public let capturedEventCount: Int
    public let updatedAt: Date

    public init(
        mode: OpenStaffMode,
        runningMode: OpenStaffMode?,
        observesTeacherActions: Bool,
        captureRunning: Bool,
        teacherPaused: Bool,
        currentApp: LearningSurfaceAppContext,
        status: LearningActivityStatus,
        statusReason: String,
        matchedRule: LearningStatusRuleMatch?,
        lastSuccessfulWriteAt: Date?,
        activeSessionId: String?,
        capturedEventCount: Int,
        updatedAt: Date
    ) {
        self.mode = mode
        self.runningMode = runningMode
        self.observesTeacherActions = observesTeacherActions
        self.captureRunning = captureRunning
        self.teacherPaused = teacherPaused
        self.currentApp = currentApp
        self.status = status
        self.statusReason = statusReason
        self.matchedRule = matchedRule
        self.lastSuccessfulWriteAt = lastSuccessfulWriteAt
        self.activeSessionId = activeSessionId
        self.capturedEventCount = capturedEventCount
        self.updatedAt = updatedAt
    }

    public var isActivelyLearning: Bool {
        status == .on && captureRunning
    }

    public var canPauseOrResumeInOneClick: Bool {
        runningMode != nil && observesTeacherActions
    }

    public static func initial(
        selectedMode: OpenStaffMode,
        lastSuccessfulWriteAt: Date? = nil,
        updatedAt: Date = Date()
    ) -> LearningSessionState {
        LearningSessionStateResolver.resolve(
            LearningSessionStateInput(
                selectedMode: selectedMode,
                runningMode: nil,
                observesTeacherActions: false,
                captureRunning: false,
                teacherPaused: false,
                currentApp: .unknown,
                exclusionMatch: nil,
                sensitiveMatch: nil,
                lastSuccessfulWriteAt: lastSuccessfulWriteAt,
                activeSessionId: nil,
                capturedEventCount: 0,
                updatedAt: updatedAt
            )
        )
    }
}

public enum LearningSessionStateResolver {
    public static func resolve(_ input: LearningSessionStateInput) -> LearningSessionState {
        let mode = input.runningMode ?? input.selectedMode
        let status: LearningActivityStatus
        let statusReason: String
        let matchedRule: LearningStatusRuleMatch?

        if input.runningMode == nil || !input.observesTeacherActions {
            status = .paused
            statusReason = "当前模式未开启学习采集。"
            matchedRule = nil
        } else if input.teacherPaused {
            status = .paused
            statusReason = "老师已手动暂停学习。"
            matchedRule = nil
        } else if let exclusionMatch = input.exclusionMatch {
            status = .excluded
            statusReason = "当前应用已被排除：\(exclusionMatch.displayName)。"
            matchedRule = exclusionMatch
        } else if let sensitiveMatch = input.sensitiveMatch {
            status = .sensitiveMuted
            statusReason = "当前窗口命中敏感场景：\(sensitiveMatch.displayName)。"
            matchedRule = sensitiveMatch
        } else if input.captureRunning {
            status = .on
            statusReason = "正在记录老师操作并持续落盘。"
            matchedRule = nil
        } else {
            status = .paused
            statusReason = "学习采集等待恢复。"
            matchedRule = nil
        }

        return LearningSessionState(
            mode: mode,
            runningMode: input.runningMode,
            observesTeacherActions: input.observesTeacherActions,
            captureRunning: input.captureRunning,
            teacherPaused: input.teacherPaused,
            currentApp: input.currentApp,
            status: status,
            statusReason: statusReason,
            matchedRule: matchedRule,
            lastSuccessfulWriteAt: input.lastSuccessfulWriteAt,
            activeSessionId: input.activeSessionId,
            capturedEventCount: input.capturedEventCount,
            updatedAt: input.updatedAt
        )
    }
}
