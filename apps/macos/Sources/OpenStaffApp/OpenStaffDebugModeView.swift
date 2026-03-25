import Foundation
import SwiftUI

struct OpenStaffDebugModeView: View {
    @ObservedObject var dashboardViewModel: OpenStaffDashboardViewModel

    @State private var workspaceSnapshot = DashboardDebugWorkspaceSnapshot.capture()
    @State private var quickFeedbackProbeNote = ""
    @State private var quickFeedbackProbeStatusMessage: String?
    @State private var quickFeedbackProbeStatusSucceeded = true
    @State private var quickFeedbackProbeDisableFixLocator = true
    @State private var quickFeedbackProbeDisableReteach = true
    @State private var quickFeedbackProbeRequireRevisionNote = true

    private var diagnostics: [DashboardDebugDiagnostic] {
        DashboardDebugDiagnosticsBuilder.build(
            input: dashboardViewModel.debugDiagnosticsInput,
            workspaceSnapshot: workspaceSnapshot
        )
    }

    private var errorCount: Int {
        diagnostics.filter { $0.severity == .error }.count
    }

    private var warningCount: Int {
        diagnostics.filter { $0.severity == .warning }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                debugControlSection
                diagnosticsSection
                componentProbeSection
                stateLogSection
                workspaceSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 980, minHeight: 720)
        .task {
            refreshDebugSnapshot(promptAccessibilityPermission: false)
        }
    }

    private var headerSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("调试模式")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("用于集中查看组件状态、错误聚合、状态机日志和工作区健康度，方便开发定位 UI / 流程问题。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("工作区")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(workspaceSnapshot.repositoryRootPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }

                HStack(spacing: 12) {
                    DashboardDebugMetricCard(
                        title: "错误",
                        value: "\(errorCount)",
                        subtitle: "需要优先处理",
                        tint: .red
                    )
                    DashboardDebugMetricCard(
                        title: "警告",
                        value: "\(warningCount)",
                        subtitle: "建议排查",
                        tint: .orange
                    )
                    DashboardDebugMetricCard(
                        title: "状态机日志",
                        value: "\(dashboardViewModel.orchestratorLogEntries.count)",
                        subtitle: "最近切换记录",
                        tint: .blue
                    )
                    DashboardDebugMetricCard(
                        title: "目录探针",
                        value: "\(workspaceSnapshot.entries.count)",
                        subtitle: "工作区节点",
                        tint: .green
                    )
                }
            }
            .padding(.top, 4)
        } label: {
            Label("调试总览", systemImage: "ladybug.fill")
        }
    }

    private var debugControlSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Button("刷新调试快照") {
                        refreshDebugSnapshot(promptAccessibilityPermission: false)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("刷新并申请辅助功能权限") {
                        refreshDebugSnapshot(promptAccessibilityPermission: true)
                    }
                    .buttonStyle(.bordered)

                    Button(dashboardViewModel.learningPauseResumeActionTitle) {
                        dashboardViewModel.toggleLearningPauseResume()
                        refreshWorkspaceSnapshot()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!dashboardViewModel.canToggleLearningPauseResume)

                    Button(dashboardViewModel.emergencyStopActive ? "解除紧急停止" : "触发紧急停止") {
                        if dashboardViewModel.emergencyStopActive {
                            dashboardViewModel.releaseEmergencyStop()
                        } else {
                            dashboardViewModel.activateEmergencyStop(source: .uiButton)
                        }
                        refreshWorkspaceSnapshot()
                    }
                    .buttonStyle(.bordered)
                    .tint(dashboardViewModel.emergencyStopActive ? .orange : .red)
                }

                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Toggle("老师已确认", isOn: $dashboardViewModel.guardInputs.teacherConfirmed)
                        Toggle("知识已就绪", isOn: $dashboardViewModel.guardInputs.learnedKnowledgeReady)
                    }
                    GridRow {
                        Toggle("执行计划已就绪", isOn: $dashboardViewModel.guardInputs.executionPlanReady)
                        Toggle("存在待确认建议", isOn: $dashboardViewModel.guardInputs.pendingAssistSuggestion)
                    }
                    GridRow {
                        Toggle(
                            "紧急停止守卫",
                            isOn: Binding(
                                get: { dashboardViewModel.guardInputs.emergencyStopActive },
                                set: { isOn in
                                    if isOn {
                                        dashboardViewModel.activateEmergencyStop(source: .uiButton)
                                    } else {
                                        dashboardViewModel.releaseEmergencyStop()
                                    }
                                }
                            )
                        )
                        Spacer(minLength: 0)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("模式启动 / 切换探针")
                        .font(.headline)
                    Text("“启动/停止运行”会走真实模式流程；“仅请求切换”只验证状态机守卫，不启动对应模式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(OpenStaffMode.allCases, id: \.self) { mode in
                        HStack(spacing: 10) {
                            Text(dashboardViewModel.modeDisplayName(for: mode))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(debugModeColor(mode))
                                .frame(width: 96, alignment: .leading)

                            Text(modeSummary(mode))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button(dashboardViewModel.isModeRunning(mode) ? "停止运行" : "启动运行") {
                                dashboardViewModel.toggleMode(mode)
                                refreshWorkspaceSnapshot()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!dashboardViewModel.canToggleMode(mode))
                            .tint(dashboardViewModel.isModeRunning(mode) ? .red : debugModeColor(mode))

                            Button("仅请求切换") {
                                dashboardViewModel.requestModeChange(to: mode)
                            }
                            .buttonStyle(.bordered)
                            .disabled(dashboardViewModel.currentMode == mode)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("调试控制", systemImage: "switch.2")
        }
    }

    private var diagnosticsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if diagnostics.isEmpty {
                    Text("当前没有聚合到需要提示的错误或警告。")
                        .font(.callout)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ForEach(diagnostics) { diagnostic in
                        DashboardDebugDiagnosticCard(diagnostic: diagnostic)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("错误与警告聚合", systemImage: "exclamationmark.triangle.fill")
        }
    }

    private var componentProbeSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text("关键组件交互探针")
                    .font(.headline)
                Text("上半部分展示真实状态组件；下半部分提供不会写入真实数据的沙盒交互，用于排查布局、禁用态与交互回调。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 12) {
                    GroupBox("Learning Status Surface") {
                        LearningStatusSurfaceCard(
                            state: dashboardViewModel.learningSessionState,
                            modeDisplayName: dashboardViewModel.modeDisplayName(for: dashboardViewModel.learningSessionState.mode),
                            actionTitle: dashboardViewModel.learningPauseResumeActionTitle,
                            actionEnabled: dashboardViewModel.canToggleLearningPauseResume,
                            onAction: {
                                dashboardViewModel.toggleLearningPauseResume()
                            }
                        )
                        .padding(.top, 4)
                    }

                    GroupBox("权限状态组件") {
                        VStack(alignment: .leading, spacing: 8) {
                            PermissionRow(
                                title: "辅助功能权限",
                                granted: dashboardViewModel.permissionSnapshot.accessibilityTrusted
                            )
                            PermissionRow(
                                title: "数据目录可写",
                                granted: dashboardViewModel.permissionSnapshot.dataDirectoryWritable
                            )
                        }
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GroupBox("Quick Feedback Bar 沙盒") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Toggle("模拟 fix locator 不可用", isOn: $quickFeedbackProbeDisableFixLocator)
                            Toggle("模拟 reteach 不可用", isOn: $quickFeedbackProbeDisableReteach)
                            Toggle("模拟 needs revision 需备注", isOn: $quickFeedbackProbeRequireRevisionNote)
                        }

                        TeacherQuickFeedbackBar(
                            actions: TeacherQuickFeedbackAction.quickActions,
                            note: $quickFeedbackProbeNote,
                            statusMessage: quickFeedbackProbeStatusMessage,
                            statusSucceeded: quickFeedbackProbeStatusSucceeded,
                            disabledReason: quickFeedbackProbeDisabledReason(for:),
                            onSubmit: submitQuickFeedbackProbe(action:)
                        )
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.top, 4)
        } label: {
            Label("组件探针", systemImage: "slider.horizontal.3")
        }
    }

    private var stateLogSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    GroupBox("实时状态快照") {
                        VStack(alignment: .leading, spacing: 8) {
                            DashboardDebugFactRow(title: "当前模式", value: dashboardViewModel.modeStatusSummary)
                            DashboardDebugFactRow(title: "状态码", value: dashboardViewModel.currentStatusCode)
                            DashboardDebugFactRow(
                                title: "能力白名单",
                                value: dashboardViewModel.currentCapabilities.isEmpty
                                    ? "无"
                                    : dashboardViewModel.currentCapabilities.joined(separator: ", ")
                            )
                            DashboardDebugFactRow(title: "采集状态", value: dashboardViewModel.captureStatusText ?? "当前未运行采集")
                            DashboardDebugFactRow(title: "紧急停止", value: dashboardViewModel.emergencyStopStatusText)
                            if let transitionMessage = dashboardViewModel.transitionMessage,
                               !transitionMessage.isEmpty {
                                DashboardDebugFactRow(title: "最近切换消息", value: transitionMessage)
                            }
                            if !dashboardViewModel.unmetRequirementsText.isEmpty {
                                DashboardDebugFactRow(title: "未满足守卫", value: dashboardViewModel.unmetRequirementsText)
                            }
                        }
                        .padding(.top, 4)
                    }

                    GroupBox("选中对象调试信息") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let log = dashboardViewModel.selectedExecutionLog {
                                DashboardDebugFactRow(title: "选中日志", value: log.id)
                                DashboardDebugFactRow(title: "日志状态", value: log.status)
                                DashboardDebugFactRow(title: "日志路径", value: "\(log.sourceFilePath):\(log.lineNumber)")
                                if let errorCode = log.errorCode {
                                    DashboardDebugFactRow(title: "日志错误码", value: errorCode)
                                }
                            } else {
                                DashboardDebugFactRow(title: "选中日志", value: "无")
                            }

                            if let skill = dashboardViewModel.selectedLearnedSkill {
                                DashboardDebugFactRow(title: "选中技能", value: skill.skillName)
                                DashboardDebugFactRow(title: "技能目录", value: skill.skillDirectoryPath)
                                DashboardDebugFactRow(title: "预检", value: skill.preflight.summary)
                            } else {
                                DashboardDebugFactRow(title: "选中技能", value: "无")
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                GroupBox("最近状态机日志") {
                    let entries = Array(dashboardViewModel.orchestratorLogEntries.prefix(12))
                    if entries.isEmpty {
                        Text("暂无状态机日志。可尝试点击“仅请求切换”或启动/停止模式。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                                DashboardOrchestratorLogCard(entry: entry)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("状态与日志", systemImage: "list.bullet.rectangle.portrait")
        }
    }

    private var workspaceSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("采样时间：\(OpenStaffDateFormatter.displayString(from: workspaceSnapshot.capturedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("重新扫描目录") {
                        refreshWorkspaceSnapshot()
                    }
                    .buttonStyle(.bordered)
                }

                ForEach(workspaceSnapshot.entries) { entry in
                    DashboardWorkspaceEntryCard(entry: entry)
                }
            }
            .padding(.top, 4)
        } label: {
            Label("工作区探针", systemImage: "externaldrive.fill.badge.wifi")
        }
    }

    private func refreshDebugSnapshot(promptAccessibilityPermission: Bool) {
        dashboardViewModel.refreshDashboard(promptAccessibilityPermission: promptAccessibilityPermission)
        refreshWorkspaceSnapshot()
    }

    private func refreshWorkspaceSnapshot() {
        workspaceSnapshot = DashboardDebugWorkspaceSnapshot.capture()
    }

    private func modeSummary(_ mode: OpenStaffMode) -> String {
        if dashboardViewModel.isModeRunning(mode) {
            return "运行中"
        }
        if dashboardViewModel.currentMode == mode {
            return "当前状态机所在模式"
        }
        if dashboardViewModel.selectedMode == mode {
            return "当前 UI 选中模式"
        }
        return "待机"
    }

    private func quickFeedbackProbeDisabledReason(
        for action: TeacherQuickFeedbackAction
    ) -> String? {
        switch action {
        case .fixLocator where quickFeedbackProbeDisableFixLocator:
            return "调试沙盒：模拟当前日志没有结构化 locator 修复入口。"
        case .reteach where quickFeedbackProbeDisableReteach:
            return "调试沙盒：模拟当前日志没有重示教入口。"
        case .needsRevision
        where quickFeedbackProbeRequireRevisionNote
            && quickFeedbackProbeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return "调试沙盒：模拟 needs revision 提交前必须填写备注。"
        default:
            return nil
        }
    }

    private func submitQuickFeedbackProbe(action: TeacherQuickFeedbackAction) {
        let trimmedNote = quickFeedbackProbeNote.trimmingCharacters(in: .whitespacesAndNewlines)
        quickFeedbackProbeStatusSucceeded = true
        quickFeedbackProbeStatusMessage = "沙盒回调已触发：\(action.displayName) @ \(OpenStaffDateFormatter.displayString(from: Date()))"
        if !trimmedNote.isEmpty {
            quickFeedbackProbeStatusMessage?.append(contentsOf: " · note=\(trimmedNote)")
        }
    }

    private func debugModeColor(_ mode: OpenStaffMode) -> Color {
        switch mode {
        case .teaching:
            return .green
        case .assist:
            return .blue
        case .student:
            return .orange
        }
    }
}

struct DashboardDebugDiagnosticsInput {
    let selectedMode: OpenStaffMode
    let currentMode: OpenStaffMode
    let runningMode: OpenStaffMode?
    let modeStatusSummary: String
    let currentStatusCode: String
    let transitionMessage: String?
    let transitionAccepted: Bool?
    let unmetRequirements: [ModeTransitionRequirement]
    let permissionSnapshot: PermissionSnapshot
    let captureStatusText: String?
    let activeObservationSessionId: String?
    let capturedEventCount: Int
    let learningSessionState: LearningSessionState
    let quickFeedbackStatusMessage: String?
    let quickFeedbackSucceeded: Bool
    let teachingSkillStatusMessage: String?
    let teachingSkillStatusSucceeded: Bool
    let teachingSkillProcessing: Bool
    let skillActionStatusMessage: String?
    let skillActionSucceeded: Bool
    let skillActionProcessing: Bool
    let learningPrivacyStatusMessage: String?
    let learningPrivacyStatusSucceeded: Bool
    let executorBackendDescription: String
    let usesHelperExecutorBackend: Bool
    let executorHelperPath: String?
    let isObservationCaptureRunning: Bool
    let currentCapabilities: [String]
    let selectedExecutionLog: ExecutionLogSummary?
    let selectedExecutionReviewDetail: ExecutionReviewDetail?
    let selectedLearnedSkill: LearnedSkillSummary?
    let selectedSkillDriftReport: SkillDriftReport?
    let selectedSkillRepairPlan: SkillRepairPlan?
}

enum DashboardDebugDiagnosticSeverity: Int, Comparable {
    case error = 0
    case warning = 1
    case info = 2

    static func < (lhs: DashboardDebugDiagnosticSeverity, rhs: DashboardDebugDiagnosticSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .error:
            return "ERROR"
        case .warning:
            return "WARNING"
        case .info:
            return "INFO"
        }
    }

    var color: Color {
        switch self {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        }
    }
}

struct DashboardDebugDiagnosticDetail: Identifiable, Equatable {
    let key: String
    let value: String

    var id: String {
        "\(key)|\(value)"
    }
}

struct DashboardDebugDiagnostic: Identifiable, Equatable {
    let severity: DashboardDebugDiagnosticSeverity
    let source: String
    let title: String
    let message: String
    let details: [DashboardDebugDiagnosticDetail]

    var id: String {
        "\(severity.rawValue)|\(source)|\(title)|\(message)"
    }
}

enum DashboardDebugDiagnosticsBuilder {
    static func build(
        input: DashboardDebugDiagnosticsInput,
        workspaceSnapshot: DashboardDebugWorkspaceSnapshot
    ) -> [DashboardDebugDiagnostic] {
        var diagnostics: [DashboardDebugDiagnostic] = []

        if !input.permissionSnapshot.dataDirectoryWritable {
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: .error,
                    source: "workspace",
                    title: "数据目录不可写",
                    message: "OpenStaff 当前无法写入学习和日志目录，教学/辅助/学生模式都会受影响。",
                    details: [
                        DashboardDebugDiagnosticDetail(
                            key: "path",
                            value: workspaceSnapshot.entry(named: "data")?.path ?? OpenStaffWorkspacePaths.dataDirectory.path
                        )
                    ]
                )
            )
        }

        if !input.permissionSnapshot.accessibilityTrusted {
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: .warning,
                    source: "permissions",
                    title: "辅助功能权限未授权",
                    message: "窗口标题、窗口 ID、部分 AX 语义上下文会降级，GUI 采集与后续 replay/repair 的定位质量会下降。",
                    details: [
                        DashboardDebugDiagnosticDetail(key: "captureRunning", value: input.isObservationCaptureRunning ? "true" : "false"),
                        DashboardDebugDiagnosticDetail(key: "backend", value: input.executorBackendDescription)
                    ]
                )
            )
        }

        if let transitionMessage = normalized(input.transitionMessage) {
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: input.transitionAccepted == false ? .error : .info,
                    source: "mode_transition",
                    title: input.transitionAccepted == false ? "模式切换被拒绝" : "最近一次模式切换",
                    message: transitionMessage,
                    details: [
                        DashboardDebugDiagnosticDetail(key: "status", value: input.currentStatusCode),
                        DashboardDebugDiagnosticDetail(key: "currentMode", value: input.currentMode.rawValue),
                        DashboardDebugDiagnosticDetail(key: "selectedMode", value: input.selectedMode.rawValue)
                    ] + unmetRequirementDetails(input.unmetRequirements)
                )
            )
        }

        if input.learningSessionState.status != .on {
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: learningStateSeverity(input.learningSessionState.status),
                    source: "learning_surface",
                    title: "学习状态当前不在 learning on",
                    message: input.learningSessionState.statusReason,
                    details: learningStateDetails(input.learningSessionState)
                )
            )
        }

        if let quickFeedbackStatusMessage = normalized(input.quickFeedbackStatusMessage) {
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: input.quickFeedbackSucceeded ? .info : .error,
                    source: "quick_feedback",
                    title: input.quickFeedbackSucceeded ? "Quick Feedback 最近一次提交结果" : "Quick Feedback 提交失败",
                    message: quickFeedbackStatusMessage,
                    details: []
                )
            )
        }

        if input.teachingSkillProcessing {
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: .info,
                    source: "teaching_pipeline",
                    title: "教学后处理正在执行",
                    message: "当前正在执行知识到 Skill 的后处理链路。",
                    details: []
                )
            )
        } else if let teachingSkillStatusMessage = normalized(input.teachingSkillStatusMessage) {
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: input.teachingSkillStatusSucceeded ? .info : .error,
                    source: "teaching_pipeline",
                    title: input.teachingSkillStatusSucceeded ? "教学后处理最近状态" : "教学后处理失败",
                    message: teachingSkillStatusMessage,
                    details: []
                )
            )
        }

        if input.skillActionProcessing {
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: .info,
                    source: "skill_runtime",
                    title: "技能动作正在执行",
                    message: "当前正在运行技能、审核技能或执行漂移检测。",
                    details: []
                )
            )
        } else if let skillActionStatusMessage = normalized(input.skillActionStatusMessage) {
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: input.skillActionSucceeded ? .info : .error,
                    source: "skill_runtime",
                    title: input.skillActionSucceeded ? "技能动作最近状态" : "技能动作失败",
                    message: skillActionStatusMessage,
                    details: helperPathDetails(
                        usesHelperExecutorBackend: input.usesHelperExecutorBackend,
                        executorHelperPath: input.executorHelperPath
                    )
                )
            )
        }

        if let learningPrivacyStatusMessage = normalized(input.learningPrivacyStatusMessage) {
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: input.learningPrivacyStatusSucceeded ? .info : .error,
                    source: "privacy_panel",
                    title: input.learningPrivacyStatusSucceeded ? "隐私面板最近状态" : "隐私面板保存失败",
                    message: learningPrivacyStatusMessage,
                    details: []
                )
            )
        }

        if let selectedExecutionLog = input.selectedExecutionLog,
           let executionDiagnostic = executionLogDiagnostic(for: selectedExecutionLog) {
            diagnostics.append(executionDiagnostic)
        }

        if let selectedExecutionReviewDetail = input.selectedExecutionReviewDetail,
           selectedExecutionReviewDetail.hasActionableRepair {
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: .warning,
                    source: "execution_review",
                    title: "当前选中日志存在结构化修复入口",
                    message: "该日志已经可以直接派生修 locator 或重示教动作，适合联调 review/repair 链路。",
                    details: [
                        DashboardDebugDiagnosticDetail(
                            key: "skill",
                            value: selectedExecutionReviewDetail.skillName ?? "unknown-skill"
                        ),
                        DashboardDebugDiagnosticDetail(
                            key: "knowledgeItemId",
                            value: selectedExecutionReviewDetail.knowledgeItemId ?? "unknown-knowledge"
                        )
                    ]
                )
            )
        }

        if let selectedLearnedSkill = input.selectedLearnedSkill {
            diagnostics.append(contentsOf: skillDiagnostics(for: selectedLearnedSkill))
        }

        if let selectedSkillDriftReport = input.selectedSkillDriftReport,
           selectedSkillDriftReport.status == .driftDetected {
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: .warning,
                    source: "skill_drift",
                    title: "选中技能检测到漂移",
                    message: selectedSkillDriftReport.summary,
                    details: [
                        DashboardDebugDiagnosticDetail(key: "dominantDrift", value: selectedSkillDriftReport.dominantDriftKind.rawValue),
                        DashboardDebugDiagnosticDetail(key: "findingCount", value: "\(selectedSkillDriftReport.findings.count)")
                    ]
                )
            )
        }

        if let selectedSkillRepairPlan = input.selectedSkillRepairPlan,
           selectedSkillRepairPlan.status == .actionRequired {
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: .warning,
                    source: "skill_repair",
                    title: "当前技能已有修复建议",
                    message: selectedSkillRepairPlan.summary,
                    details: [
                        DashboardDebugDiagnosticDetail(key: "actionCount", value: "\(selectedSkillRepairPlan.actions.count)"),
                        DashboardDebugDiagnosticDetail(
                            key: "recommendedRepairVersion",
                            value: selectedSkillRepairPlan.recommendedRepairVersion.map(String.init) ?? "n/a"
                        )
                    ]
                )
            )
        }

        for entry in workspaceSnapshot.entries where entry.critical && !entry.exists {
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: .error,
                    source: "workspace",
                    title: "关键目录缺失：\(entry.name)",
                    message: "该目录不存在，依赖它的 UI 面板与流程会表现为空或直接失败。",
                    details: [
                        DashboardDebugDiagnosticDetail(key: "path", value: entry.path)
                    ]
                )
            )
        }

        return diagnostics.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity < rhs.severity
            }
            if lhs.source != rhs.source {
                return lhs.source < rhs.source
            }
            if lhs.title != rhs.title {
                return lhs.title < rhs.title
            }
            return lhs.message < rhs.message
        }
    }

    private static func executionLogDiagnostic(
        for log: ExecutionLogSummary
    ) -> DashboardDebugDiagnostic? {
        let status = log.status.lowercased()
        let severity: DashboardDebugDiagnosticSeverity
        if log.errorCode != nil || status.contains("fail") {
            severity = .error
        } else if status.contains("block") {
            severity = .warning
        } else {
            return nil
        }

        return DashboardDebugDiagnostic(
            severity: severity,
            source: "execution_log",
            title: "当前选中日志存在失败/阻断信号",
            message: log.message,
            details: [
                DashboardDebugDiagnosticDetail(key: "status", value: log.status),
                DashboardDebugDiagnosticDetail(key: "errorCode", value: log.errorCode ?? "none"),
                DashboardDebugDiagnosticDetail(key: "component", value: log.component ?? "unknown"),
                DashboardDebugDiagnosticDetail(key: "path", value: "\(log.sourceFilePath):\(log.lineNumber)")
            ]
        )
    }

    private static func skillDiagnostics(
        for skill: LearnedSkillSummary
    ) -> [DashboardDebugDiagnostic] {
        var diagnostics: [DashboardDebugDiagnostic] = []

        switch skill.preflight.status {
        case .failed:
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: .error,
                    source: "skill_preflight",
                    title: "选中技能预检失败",
                    message: skill.preflight.summary,
                    details: [
                        DashboardDebugDiagnosticDetail(key: "skill", value: skill.skillName),
                        DashboardDebugDiagnosticDetail(key: "path", value: skill.skillDirectoryPath)
                    ]
                )
            )
        case .needsTeacherConfirmation:
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: .warning,
                    source: "skill_preflight",
                    title: "选中技能需要老师确认",
                    message: skill.preflight.summary,
                    details: [
                        DashboardDebugDiagnosticDetail(key: "skill", value: skill.skillName)
                    ]
                )
            )
        case .passed:
            break
        }

        if !skill.llmOutputAccepted {
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: .warning,
                    source: "skill_bundle",
                    title: "选中技能的 LLM 输出未通过校验",
                    message: "当前 skill 是 fallback 或未验收结果，建议优先检查生成链路与输入结果。",
                    details: [
                        DashboardDebugDiagnosticDetail(key: "skill", value: skill.skillName),
                        DashboardDebugDiagnosticDetail(key: "skillJSON", value: skill.skillJSONPath)
                    ]
                )
            )
        }

        if let review = skill.review,
           review.decision == .rejected {
            diagnostics.append(
                DashboardDebugDiagnostic(
                    severity: .warning,
                    source: "skill_review",
                    title: "选中技能已被驳回",
                    message: "当前 skill 已被老师显式驳回，不应继续作为通过链路样本。",
                    details: [
                        DashboardDebugDiagnosticDetail(
                            key: "reviewedAt",
                            value: OpenStaffDateFormatter.displayString(from: review.timestamp)
                        )
                    ]
                )
            )
        }

        return diagnostics
    }

    private static func helperPathDetails(
        usesHelperExecutorBackend: Bool,
        executorHelperPath: String?
    ) -> [DashboardDebugDiagnosticDetail] {
        guard usesHelperExecutorBackend else {
            return []
        }
        return [
            DashboardDebugDiagnosticDetail(
                key: "helperPath",
                value: normalized(executorHelperPath) ?? "未激活"
            )
        ]
    }

    private static func unmetRequirementDetails(
        _ requirements: [ModeTransitionRequirement]
    ) -> [DashboardDebugDiagnosticDetail] {
        guard !requirements.isEmpty else {
            return []
        }
        return [
            DashboardDebugDiagnosticDetail(
                key: "unmetRequirements",
                value: requirements.map(\.rawValue).joined(separator: ", ")
            )
        ]
    }

    private static func learningStateSeverity(
        _ status: LearningActivityStatus
    ) -> DashboardDebugDiagnosticSeverity {
        switch status {
        case .on:
            return .info
        case .paused:
            return .warning
        case .excluded, .sensitiveMuted:
            return .info
        }
    }

    private static func learningStateDetails(
        _ state: LearningSessionState
    ) -> [DashboardDebugDiagnosticDetail] {
        var details: [DashboardDebugDiagnosticDetail] = [
            DashboardDebugDiagnosticDetail(key: "status", value: state.status.rawValue),
            DashboardDebugDiagnosticDetail(key: "currentApp", value: "\(state.currentApp.appName) (\(state.currentApp.appBundleId))"),
            DashboardDebugDiagnosticDetail(key: "captureRunning", value: state.captureRunning ? "true" : "false"),
            DashboardDebugDiagnosticDetail(key: "eventCount", value: "\(state.capturedEventCount)")
        ]
        if let matchedRule = state.matchedRule {
            details.append(
                DashboardDebugDiagnosticDetail(
                    key: "matchedRule",
                    value: "\(matchedRule.ruleId) · \(matchedRule.displayName)"
                )
            )
        }
        if let activeSessionId = state.activeSessionId {
            details.append(
                DashboardDebugDiagnosticDetail(
                    key: "activeSessionId",
                    value: activeSessionId
                )
            )
        }
        return details
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct DashboardDebugWorkspaceRoot {
    let name: String
    let url: URL
    let critical: Bool
}

struct DashboardDebugWorkspaceEntry: Identifiable, Equatable {
    let name: String
    let path: String
    let exists: Bool
    let isDirectory: Bool
    let isWritable: Bool
    let fileCount: Int
    let latestModifiedAt: Date?
    let latestFilePath: String?
    let critical: Bool

    var id: String {
        name
    }
}

struct DashboardDebugWorkspaceSnapshot: Equatable {
    let capturedAt: Date
    let repositoryRootPath: String
    let entries: [DashboardDebugWorkspaceEntry]

    static func capture(fileManager: FileManager = .default) -> DashboardDebugWorkspaceSnapshot {
        capture(
            roots: [
                DashboardDebugWorkspaceRoot(name: "data", url: OpenStaffWorkspacePaths.dataDirectory, critical: true),
                DashboardDebugWorkspaceRoot(name: "logs", url: OpenStaffWorkspacePaths.logsDirectory, critical: false),
                DashboardDebugWorkspaceRoot(name: "raw-events", url: OpenStaffWorkspacePaths.rawEventsDirectory, critical: false),
                DashboardDebugWorkspaceRoot(name: "task-chunks", url: OpenStaffWorkspacePaths.taskChunksDirectory, critical: false),
                DashboardDebugWorkspaceRoot(name: "knowledge", url: OpenStaffWorkspacePaths.knowledgeDirectory, critical: false),
                DashboardDebugWorkspaceRoot(name: "feedback", url: OpenStaffWorkspacePaths.feedbackDirectory, critical: false),
                DashboardDebugWorkspaceRoot(name: "reports", url: OpenStaffWorkspacePaths.reportsDirectory, critical: false),
                DashboardDebugWorkspaceRoot(name: "preferences", url: OpenStaffWorkspacePaths.preferencesDirectory, critical: false),
                DashboardDebugWorkspaceRoot(name: "skills-pending", url: OpenStaffWorkspacePaths.skillsPendingDirectory, critical: false),
                DashboardDebugWorkspaceRoot(name: "skills-done", url: OpenStaffWorkspacePaths.skillsDoneDirectory, critical: false),
                DashboardDebugWorkspaceRoot(name: "skills-repairs", url: OpenStaffWorkspacePaths.skillsRepairDirectory, critical: false)
            ],
            fileManager: fileManager
        )
    }

    static func capture(
        roots: [DashboardDebugWorkspaceRoot],
        fileManager: FileManager = .default
    ) -> DashboardDebugWorkspaceSnapshot {
        let entries = roots.map { root in
            captureEntry(root: root, fileManager: fileManager)
        }

        return DashboardDebugWorkspaceSnapshot(
            capturedAt: Date(),
            repositoryRootPath: OpenStaffWorkspacePaths.repositoryRoot.path,
            entries: entries
        )
    }

    func entry(named name: String) -> DashboardDebugWorkspaceEntry? {
        entries.first { $0.name == name }
    }

    private static func captureEntry(
        root: DashboardDebugWorkspaceRoot,
        fileManager: FileManager
    ) -> DashboardDebugWorkspaceEntry {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: root.url.path, isDirectory: &isDirectory)
        let isWritable = exists && fileManager.isWritableFile(atPath: root.url.path)

        guard exists, isDirectory.boolValue else {
            return DashboardDebugWorkspaceEntry(
                name: root.name,
                path: root.url.path,
                exists: exists,
                isDirectory: isDirectory.boolValue,
                isWritable: isWritable,
                fileCount: 0,
                latestModifiedAt: nil,
                latestFilePath: nil,
                critical: root.critical
            )
        }

        let enumerator = fileManager.enumerator(
            at: root.url,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var fileCount = 0
        var latestModifiedAt: Date?
        var latestFilePath: String?

        while let fileURL = enumerator?.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }
            fileCount += 1
            if let modifiedAt = values.contentModificationDate,
               latestModifiedAt == nil || modifiedAt > (latestModifiedAt ?? .distantPast) {
                latestModifiedAt = modifiedAt
                latestFilePath = fileURL.path
            }
        }

        return DashboardDebugWorkspaceEntry(
            name: root.name,
            path: root.url.path,
            exists: true,
            isDirectory: true,
            isWritable: isWritable,
            fileCount: fileCount,
            latestModifiedAt: latestModifiedAt,
            latestFilePath: latestFilePath,
            critical: root.critical
        )
    }
}

private struct DashboardDebugMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tint.opacity(0.16), lineWidth: 1)
                )
        )
    }
}

private struct DashboardDebugDiagnosticCard: View {
    let diagnostic: DashboardDebugDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(diagnostic.severity.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(diagnostic.severity.color.opacity(0.16))
                    )
                    .foregroundStyle(diagnostic.severity.color)
                Text(diagnostic.source)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(diagnostic.title)
                    .font(.callout.weight(.semibold))
            }

            Text(diagnostic.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if !diagnostic.details.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(diagnostic.details) { detail in
                        DashboardDebugFactRow(title: detail.key, value: detail.value)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(diagnostic.severity.color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(diagnostic.severity.color.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

private struct DashboardOrchestratorLogCard: View {
    let entry: OrchestratorLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entry.errorCode == nil ? Color.secondary : .red)
                Text("\(entry.fromMode.rawValue) -> \(entry.toMode.rawValue)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.timestamp)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(entry.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 4) {
                DashboardDebugFactRow(title: "traceId", value: entry.traceId)
                DashboardDebugFactRow(title: "sessionId", value: entry.sessionId)
                if let taskId = entry.taskId {
                    DashboardDebugFactRow(title: "taskId", value: taskId)
                }
                if let errorCode = entry.errorCode {
                    DashboardDebugFactRow(title: "errorCode", value: errorCode)
                }
                if !entry.unmetRequirements.isEmpty {
                    DashboardDebugFactRow(
                        title: "unmetRequirements",
                        value: entry.unmetRequirements.map(\.rawValue).joined(separator: ", ")
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}

private struct DashboardWorkspaceEntryCard: View {
    let entry: DashboardDebugWorkspaceEntry

    private var statusColor: Color {
        if !entry.exists && entry.critical {
            return .red
        }
        if !entry.exists {
            return .secondary
        }
        if !entry.isWritable && entry.critical {
            return .orange
        }
        return .green
    }

    private var statusText: String {
        if !entry.exists {
            return entry.critical ? "缺失（关键）" : "缺失"
        }
        if !entry.isWritable {
            return "存在但不可写"
        }
        return "正常"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.name)
                    .font(.headline)
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                Spacer()
                Text("files \(entry.fileCount)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            DashboardDebugFactRow(title: "path", value: entry.path)
            DashboardDebugFactRow(title: "writable", value: entry.isWritable ? "true" : "false")
            if let latestModifiedAt = entry.latestModifiedAt {
                DashboardDebugFactRow(
                    title: "latestModifiedAt",
                    value: OpenStaffDateFormatter.displayString(from: latestModifiedAt)
                )
            }
            if let latestFilePath = entry.latestFilePath {
                DashboardDebugFactRow(title: "latestFile", value: latestFilePath)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(statusColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(statusColor.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

private struct DashboardDebugFactRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
