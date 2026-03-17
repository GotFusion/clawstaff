import SwiftUI

struct OpenStaffHomeView: View {
    @ObservedObject var dashboardViewModel: OpenStaffDashboardViewModel
    let openStatusWorkbench: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            OpenStaffHomeTheme.backgroundGradient(for: colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    primaryActionsCard
                    modeQuickEntryCard
                    quickFeedbackCard
                    summaryCard
                }
                .padding(20)
            }
        }
        .task {
            dashboardViewModel.startSafetyControlsIfNeeded()
            dashboardViewModel.refreshDashboard(promptAccessibilityPermission: false)
        }
    }

    private var headerCard: some View {
        OpenStaffHomeCard(
            title: "首页",
            subtitle: "OpenStaff 日常交互入口"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(dashboardViewModel.modeStatusSummary)
                    .font(.title3.weight(.semibold))
                if let captureStatusText = dashboardViewModel.captureStatusText {
                    Text(captureStatusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("当前未启动需要屏幕监控的模式。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let transitionMessage = dashboardViewModel.transitionMessage {
                    Text(transitionMessage)
                        .font(.caption)
                        .foregroundStyle(dashboardViewModel.lastTransitionAccepted ? .green : .red)
                }

                LearningStatusSurfaceCard(
                    state: dashboardViewModel.learningSessionState,
                    modeDisplayName: dashboardViewModel.modeDisplayName(for: dashboardViewModel.learningSessionState.mode),
                    actionTitle: dashboardViewModel.learningPauseResumeActionTitle,
                    actionEnabled: dashboardViewModel.canToggleLearningPauseResume,
                    onAction: {
                        dashboardViewModel.toggleLearningPauseResume()
                    }
                )

                HStack(spacing: 8) {
                    Button("查看状态工作台详情") {
                        openStatusWorkbench()
                    }
                    .buttonStyle(.borderedProminent)

                    if let refreshedAt = dashboardViewModel.lastRefreshedAt {
                        Text("最近刷新：\(OpenStaffDateFormatter.displayString(from: refreshedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var primaryActionsCard: some View {
        OpenStaffHomeCard(
            title: "主要操作",
            subtitle: "选择模式、启动运行、权限与安全控制"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker(
                    "运行模式",
                    selection: Binding(
                        get: { dashboardViewModel.selectedMode },
                        set: { dashboardViewModel.selectMode($0) }
                    )
                ) {
                    ForEach(OpenStaffMode.allCases, id: \.self) { mode in
                        Text(dashboardViewModel.modeDisplayName(for: mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(dashboardViewModel.isAnyModeRunning)

                HStack(spacing: 10) {
                    Button(dashboardViewModel.isModeRunning(dashboardViewModel.selectedMode) ? "停止当前模式" : "启动当前模式") {
                        dashboardViewModel.toggleMode(dashboardViewModel.selectedMode)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!dashboardViewModel.canToggleMode(dashboardViewModel.selectedMode))
                    .tint(
                        dashboardViewModel.isModeRunning(dashboardViewModel.selectedMode)
                            ? .red
                            : modeAccentColor(dashboardViewModel.selectedMode)
                    )

                    Button("刷新数据") {
                        dashboardViewModel.refreshDashboard(promptAccessibilityPermission: false)
                    }
                    .buttonStyle(.bordered)

                    Spacer(minLength: 0)

                    Button("申请辅助功能权限") {
                        dashboardViewModel.refreshDashboard(promptAccessibilityPermission: true)
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 10) {
                    Button("紧急停止") {
                        dashboardViewModel.activateEmergencyStop(source: .uiButton)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button("解除停止") {
                        dashboardViewModel.releaseEmergencyStop()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!dashboardViewModel.emergencyStopActive)

                    Text(dashboardViewModel.emergencyStopStatusText)
                        .font(.caption)
                        .foregroundStyle(dashboardViewModel.emergencyStopActive ? .red : .secondary)
                }
            }
        }
    }

    private var modeQuickEntryCard: some View {
        OpenStaffHomeCard(
            title: "三种模式",
            subtitle: "按场景快速切换"
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                ForEach(OpenStaffMode.allCases, id: \.self) { mode in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: modeIcon(mode))
                                .foregroundStyle(modeAccentColor(mode))
                            Text(dashboardViewModel.modeDisplayName(for: mode))
                                .font(.headline)
                            Spacer(minLength: 0)
                            Text(dashboardViewModel.isModeRunning(mode) ? "运行中" : "待机")
                                .font(.caption2)
                                .foregroundStyle(dashboardViewModel.isModeRunning(mode) ? modeAccentColor(mode) : .secondary)
                        }

                        Text(modeDescription(mode))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(dashboardViewModel.isModeRunning(mode) ? "停止" : "启动") {
                            dashboardViewModel.toggleMode(mode)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(dashboardViewModel.isModeRunning(mode) ? .red : modeAccentColor(mode))
                        .disabled(!dashboardViewModel.canToggleMode(mode))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(OpenStaffHomeTheme.secondaryCardFill(for: colorScheme))
                    )
                }
            }
        }
    }

    private var summaryCard: some View {
        OpenStaffHomeCard(
            title: "概览",
            subtitle: "详细日志、任务、知识条目请在状态工作台查看"
        ) {
            HStack(spacing: 12) {
                HomeMetricItem(title: "最近任务", value: "\(dashboardViewModel.recentTasks.count)")
                HomeMetricItem(title: "学习会话", value: "\(dashboardViewModel.learningSessions.count)")
                HomeMetricItem(title: "待审阅日志", value: "\(dashboardViewModel.executionLogs.count)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button("打开状态工作台") {
                    openStatusWorkbench()
                }
                .buttonStyle(.bordered)

                Text("状态工作台提供完整状态、学习记录与审阅反馈。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var quickFeedbackCard: some View {
        if let selectedExecutionLog = dashboardViewModel.selectedExecutionLog {
            OpenStaffHomeCard(
                title: "快速反馈",
                subtitle: "对当前选中的执行日志直接给出老师快评"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(selectedExecutionLog.message)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        "\(dashboardViewModel.modeDisplayName(for: selectedExecutionLog.mode)) · \(selectedExecutionLog.sessionId) · \(selectedExecutionLog.taskId ?? "no-task") · \(OpenStaffDateFormatter.displayString(from: selectedExecutionLog.timestamp))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let latestFeedback = dashboardViewModel.latestFeedbackForSelectedLog {
                        Text("最近反馈：\(latestFeedback.decision.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TeacherQuickFeedbackBar(
                        actions: dashboardViewModel.quickFeedbackActions,
                        note: $dashboardViewModel.quickFeedbackNoteInput,
                        statusMessage: dashboardViewModel.quickFeedbackStatusMessage,
                        statusSucceeded: dashboardViewModel.quickFeedbackWriteSucceeded,
                        disabledReason: dashboardViewModel.quickFeedbackDisabledReason(for:),
                        onSubmit: dashboardViewModel.submitTeacherFeedback(decision:)
                    )

                    HStack(spacing: 8) {
                        Button("打开状态工作台查看更多日志") {
                            openStatusWorkbench()
                        }
                        .buttonStyle(.bordered)

                        Text("默认针对当前选中的最新日志，可继续到工作台查看三栏对照。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func modeAccentColor(_ mode: OpenStaffMode) -> Color {
        switch mode {
        case .teaching:
            return Color(red: 0.10, green: 0.44, blue: 0.93)
        case .assist:
            return Color(red: 0.96, green: 0.50, blue: 0.09)
        case .student:
            return Color(red: 0.10, green: 0.63, blue: 0.33)
        }
    }

    private func modeIcon(_ mode: OpenStaffMode) -> String {
        switch mode {
        case .teaching:
            return "book.closed.circle.fill"
        case .assist:
            return "hand.raised.circle.fill"
        case .student:
            return "bolt.circle.fill"
        }
    }

    private func modeDescription(_ mode: OpenStaffMode) -> String {
        switch mode {
        case .teaching:
            return "记录老师屏幕操作并整理为结构化知识。"
        case .assist:
            return "老师主导操作，学生预测下一步并确认后执行。"
        case .student:
            return "学生依据已学知识自主执行，并输出执行日志。"
        }
    }
}

private struct OpenStaffHomeCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(OpenStaffHomeTheme.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(OpenStaffHomeTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
    }
}

private struct HomeMetricItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(minWidth: 120, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

private enum OpenStaffHomeTheme {
    static func cardFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.14, blue: 0.18).opacity(0.92)
            : Color.white.opacity(0.78)
    }

    static func secondaryCardFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.18, blue: 0.22).opacity(0.9)
            : Color.white.opacity(0.62)
    }

    static func cardBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.white.opacity(0.36)
    }

    static func backgroundGradient(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.13),
                    Color(red: 0.09, green: 0.13, blue: 0.18),
                    Color(red: 0.08, green: 0.10, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.97, blue: 1.00),
                Color(red: 0.86, green: 0.95, blue: 0.95),
                Color(red: 0.92, green: 0.92, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
