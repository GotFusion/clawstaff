import SwiftUI

struct OpenStaffModeWorkbenchView: View {
    @ObservedObject var dashboardViewModel: OpenStaffDashboardViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            OpenStaffModeWorkbenchTheme.backgroundGradient(for: colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    modeControlCard
                    statusCard
                    recentTasksCard
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
        OpenStaffModeWorkbenchCard(
            title: "模式工作台",
            subtitle: "教学 / 辅助 / 学生 · 实时运行页"
        ) {
            VStack(alignment: .leading, spacing: 8) {
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
            }
        }
    }

    private var modeControlCard: some View {
        OpenStaffModeWorkbenchCard(
            title: "模式控制",
            subtitle: "直接操作真实模式，不包含模拟流程"
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

                    Button("刷新数据") {
                        dashboardViewModel.refreshDashboard(promptAccessibilityPermission: false)
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 10) {
                    ForEach(OpenStaffMode.allCases, id: \.self) { mode in
                        Label(
                            dashboardViewModel.modeDisplayName(for: mode),
                            systemImage: dashboardViewModel.isModeRunning(mode) ? "record.circle.fill" : "circle"
                        )
                        .font(.caption)
                        .foregroundStyle(dashboardViewModel.isModeRunning(mode) ? modeAccentColor(mode) : .secondary)
                    }
                }
            }
        }
    }

    private var statusCard: some View {
        OpenStaffModeWorkbenchCard(
            title: "实时状态",
            subtitle: "状态机与能力白名单"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("状态码", value: dashboardViewModel.currentStatusCode)
                LabeledContent("紧急停止", value: dashboardViewModel.emergencyStopStatusText)
                if !dashboardViewModel.currentCapabilities.isEmpty {
                    LabeledContent(
                        "能力白名单",
                        value: dashboardViewModel.currentCapabilities.joined(separator: ", ")
                    )
                }
                if !dashboardViewModel.unmetRequirementsText.isEmpty {
                    LabeledContent("未满足守卫", value: dashboardViewModel.unmetRequirementsText)
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recentTasksCard: some View {
        OpenStaffModeWorkbenchCard(
            title: "最近任务",
            subtitle: "真实执行日志摘要"
        ) {
            if dashboardViewModel.recentTasks.isEmpty {
                Text("暂无任务记录。启动教学/辅助/学生模式后可在此查看。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(dashboardViewModel.recentTasks.prefix(8)), id: \.id) { task in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(dashboardViewModel.modeDisplayName(for: task.mode))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(modeAccentColor(task.mode))
                                Text(task.taskId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(OpenStaffDateFormatter.displayString(from: task.timestamp))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(task.message)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("status: \(task.status) · session: \(task.sessionId)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        if task.id != dashboardViewModel.recentTasks.prefix(8).last?.id {
                            Divider()
                        }
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
}

private struct OpenStaffModeWorkbenchCard<Content: View>: View {
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
                .fill(OpenStaffModeWorkbenchTheme.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(OpenStaffModeWorkbenchTheme.cardBorder(for: colorScheme), lineWidth: 1)
        )
    }
}

private enum OpenStaffModeWorkbenchTheme {
    static func cardFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.14, blue: 0.18).opacity(0.92)
            : Color.white.opacity(0.78)
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
