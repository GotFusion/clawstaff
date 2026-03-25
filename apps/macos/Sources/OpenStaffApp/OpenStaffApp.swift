import ApplicationServices
import AppKit
import Foundation
import SwiftUI

@main
struct OpenStaffApp: App {
    @StateObject private var viewModel = OpenStaffDashboardViewModel()
    @StateObject private var desktopWidgetViewModel = OpenStaffDesktopWidgetViewModel()

    var body: some Scene {
        Window("OpenStaff", id: OpenStaffSceneID.console) {
            OpenStaffRootView(
                viewModel: viewModel,
                desktopWidgetViewModel: desktopWidgetViewModel
            )
        }
        .windowResizability(.automatic)
        .defaultSize(width: 1180, height: 900)

        Window("OpenStaff 前台部件", id: OpenStaffSceneID.desktopWidget) {
            OpenStaffDesktopWidgetView(
                viewModel: desktopWidgetViewModel,
                dashboardViewModel: viewModel
            )
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 392, height: 334)

        MenuBarExtra("OpenStaff", systemImage: "graduationcap.circle") {
            OpenStaffMenuBarContentView(
                dashboardViewModel: viewModel,
                desktopWidgetViewModel: desktopWidgetViewModel
            )
        }
        .menuBarExtraStyle(.menu)
    }
}

struct OpenStaffRootView: View {
    @ObservedObject var viewModel: OpenStaffDashboardViewModel
    @ObservedObject var desktopWidgetViewModel: OpenStaffDesktopWidgetViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var hasOpenedDesktopWidget = false
    @State private var selectedTab: OpenStaffRootTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            OpenStaffHomeView(
                dashboardViewModel: viewModel,
                openStatusWorkbench: { selectedTab = .statusWorkbench }
            )
                .tag(OpenStaffRootTab.home)
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }

            OpenStaffDashboardView(viewModel: viewModel)
                .tag(OpenStaffRootTab.statusWorkbench)
                .tabItem {
                    Label("状态工作台", systemImage: "gauge.with.dots.needle.67percent")
                }

            OpenStaffDebugModeView(dashboardViewModel: viewModel)
                .tag(OpenStaffRootTab.debugMode)
                .tabItem {
                    Label("调试模式", systemImage: "ladybug.fill")
                }
        }
        .background(ConsoleWindowConfigurator(windowIdentifier: OpenStaffSceneID.console))
        .task {
            guard !hasOpenedDesktopWidget else {
                return
            }
            hasOpenedDesktopWidget = true
            if desktopWidgetViewModel.isWidgetWindowVisible {
                openWindow(id: OpenStaffSceneID.desktopWidget)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Picker(
                        "快捷模式",
                        selection: Binding(
                            get: { viewModel.selectedMode },
                            set: { viewModel.selectMode($0) }
                        )
                    ) {
                        ForEach(OpenStaffMode.allCases, id: \.self) { mode in
                            Text(viewModel.modeDisplayName(for: mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(viewModel.isAnyModeRunning)

                    Button(viewModel.isModeRunning(viewModel.selectedMode) ? "停止" : "开始") {
                        viewModel.toggleMode(viewModel.selectedMode)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canToggleMode(viewModel.selectedMode))
                    .tint(viewModel.isModeRunning(viewModel.selectedMode) ? .red : viewModel.selectedMode.color)
                }
            }
        }
    }
}

private enum OpenStaffRootTab: Hashable {
    case home
    case statusWorkbench
    case debugMode
}

private struct ConsoleWindowConfigurator: NSViewRepresentable {
    let windowIdentifier: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindowIfNeeded(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindowIfNeeded(nsView.window)
        }
    }

    private func configureWindowIfNeeded(_ window: NSWindow?) {
        guard let window else {
            return
        }

        if window.identifier?.rawValue != windowIdentifier {
            window.identifier = NSUserInterfaceItemIdentifier(windowIdentifier)
        }

        window.styleMask.remove(.borderless)
        window.styleMask.insert([.titled, .resizable, .closable, .miniaturizable])
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
        window.level = .normal
        window.collectionBehavior.remove([.stationary, .canJoinAllSpaces, .fullScreenAuxiliary])

        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }
}

struct OpenStaffDashboardView: View {
    @ObservedObject var viewModel: OpenStaffDashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("状态工作台")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("详细状态、学习记录、审阅反馈与安全控制")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        if let refreshedAt = viewModel.lastRefreshedAt {
                            Text("最近刷新：\(OpenStaffDateFormatter.displayString(from: refreshedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(viewModel.emergencyStopStatusText)
                            .font(.caption)
                            .foregroundStyle(viewModel.emergencyStopActive ? .red : .secondary)

                        HStack(spacing: 8) {
                            Button("刷新任务与权限") {
                                viewModel.refreshDashboard(promptAccessibilityPermission: false)
                            }
                            .keyboardShortcut("r", modifiers: [.command])

                            Button("申请辅助功能权限") {
                                viewModel.refreshDashboard(promptAccessibilityPermission: true)
                            }

                            Button("紧急停止") {
                                viewModel.activateEmergencyStop(source: .uiButton)
                            }
                            .keyboardShortcut(".", modifiers: [.command, .shift])
                            .buttonStyle(.borderedProminent)
                            .tint(.red)

                            Button("解除停止") {
                                viewModel.releaseEmergencyStop()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!viewModel.emergencyStopActive)
                        }
                    }
                }

                GroupBox("模式控制与守卫") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(
                            "运行模式",
                            selection: Binding(
                                get: { viewModel.selectedMode },
                                set: { viewModel.selectMode($0) }
                            )
                        ) {
                            ForEach(OpenStaffMode.allCases, id: \.self) { mode in
                                Text(viewModel.modeDisplayName(for: mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(viewModel.isAnyModeRunning)

                        HStack(spacing: 8) {
                            Button(viewModel.isModeRunning(viewModel.selectedMode) ? "停止当前选中模式" : "启动当前选中模式") {
                                viewModel.toggleMode(viewModel.selectedMode)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!viewModel.canToggleMode(viewModel.selectedMode))
                            .tint(viewModel.isModeRunning(viewModel.selectedMode) ? .red : viewModel.selectedMode.color)

                            Button("停止所有模式") {
                                guard let runningMode = viewModel.runningMode else {
                                    return
                                }
                                viewModel.stopMode(runningMode)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!viewModel.isAnyModeRunning)
                        }

                        Text("模式运行控制")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(OpenStaffMode.allCases, id: \.self) { mode in
                                HStack(spacing: 10) {
                                    Text(viewModel.modeDisplayName(for: mode))
                                        .font(.callout)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(mode.color)
                                        .frame(width: 82, alignment: .leading)

                                    Button(viewModel.isModeRunning(mode) ? "停止" : "开始") {
                                        viewModel.toggleMode(mode)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!viewModel.canToggleMode(mode))
                                    .tint(viewModel.isModeRunning(mode) ? .red : mode.color)

                                    Spacer(minLength: 0)

                                    Text(viewModel.isModeRunning(mode) ? "运行中" : "未运行")
                                        .font(.caption)
                                        .foregroundStyle(viewModel.isModeRunning(mode) ? mode.color : .secondary)
                                }
                            }
                        }

                        Text("切换守卫输入")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                            GridRow {
                                Toggle("老师已确认", isOn: $viewModel.guardInputs.teacherConfirmed)
                                Toggle("知识已就绪", isOn: $viewModel.guardInputs.learnedKnowledgeReady)
                            }
                            GridRow {
                                Toggle("执行计划已就绪", isOn: $viewModel.guardInputs.executionPlanReady)
                                Toggle("存在待确认建议", isOn: $viewModel.guardInputs.pendingAssistSuggestion)
                            }
                            GridRow {
                                Toggle(
                                    "紧急停止已激活",
                                    isOn: Binding(
                                        get: { viewModel.guardInputs.emergencyStopActive },
                                        set: { isOn in
                                            if isOn {
                                                viewModel.activateEmergencyStop(source: .uiButton)
                                            } else {
                                                viewModel.releaseEmergencyStop()
                                            }
                                        }
                                    )
                                )
                                Spacer(minLength: 0)
                            }
                        }

                        if let transitionMessage = viewModel.transitionMessage {
                            Text(transitionMessage)
                                .font(.caption)
                                .foregroundStyle(viewModel.lastTransitionAccepted ? .green : .red)
                        }

                        if let captureStatusText = viewModel.captureStatusText {
                            Text(captureStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("Learning Status Surface") {
                    LearningStatusSurfaceCard(
                        state: viewModel.learningSessionState,
                        modeDisplayName: viewModel.modeDisplayName(for: viewModel.learningSessionState.mode),
                        actionTitle: viewModel.learningPauseResumeActionTitle,
                        actionEnabled: viewModel.canToggleLearningPauseResume,
                        onAction: {
                            viewModel.toggleLearningPauseResume()
                        }
                    )
                    .padding(.top, 4)
                }

                GroupBox("Privacy / Exclusion Panel") {
                    LearningPrivacyPanel(dashboardViewModel: viewModel)
                }

                HStack(alignment: .top, spacing: 12) {
                    GroupBox("当前状态") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("当前模式", value: viewModel.modeStatusSummary)
                            LabeledContent("状态码", value: viewModel.currentStatusCode)
                            LabeledContent("采集会话", value: viewModel.activeObservationSessionId ?? "未运行")
                            LabeledContent("点击计数", value: "\(viewModel.capturedEventCount)")
                            if !viewModel.currentCapabilities.isEmpty {
                                LabeledContent("能力白名单", value: viewModel.currentCapabilities.joined(separator: ", "))
                            }
                            if !viewModel.unmetRequirementsText.isEmpty {
                                LabeledContent("未满足守卫", value: viewModel.unmetRequirementsText)
                            }
                        }
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }

                    GroupBox("权限状态") {
                        VStack(alignment: .leading, spacing: 8) {
                            PermissionRow(
                                title: "辅助功能权限",
                                granted: viewModel.permissionSnapshot.accessibilityTrusted
                            )
                            PermissionRow(
                                title: "数据目录可写",
                                granted: viewModel.permissionSnapshot.dataDirectoryWritable
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }

                    GroupBox("采集监控") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let captureStatusText = viewModel.captureStatusText {
                                Text(captureStatusText)
                                    .font(.callout)
                            } else {
                                Text("当前没有运行需要采集屏幕操作事件的模式。")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            LabeledContent(
                                "窗口上下文采集",
                                value: viewModel.permissionSnapshot.accessibilityTrusted ? "已启用" : "降级（未授权）"
                            )
                            .font(.callout)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }
                }

                GroupBox("最近任务") {
                    if viewModel.recentTasks.isEmpty {
                        Text("暂无最近任务记录。可先运行一次教学/辅助/学生流程后刷新。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        List(viewModel.recentTasks) { task in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(viewModel.modeDisplayName(for: task.mode))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(task.mode.color)
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
                                Text("status: \(task.status) · session: \(task.sessionId)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .listStyle(.inset)
                        .frame(minHeight: 260)
                    }
                }

                GroupBox("学习记录与知识浏览") {
                if viewModel.learningSessions.isEmpty {
                    Text("暂无学习会话数据。可先运行 capture/slice/knowledge，再点击刷新。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("会话列表")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            List(
                                selection: Binding(
                                    get: { viewModel.selectedLearningSessionId },
                                    set: { viewModel.selectLearningSession($0) }
                                )
                            ) {
                                ForEach(viewModel.learningSessions) { session in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.sessionId)
                                            .font(.callout)
                                        Text("任务 \(session.taskCount) · 知识 \(session.knowledgeItemCount)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        if let endedAt = session.endedAt {
                                            Text("最近活动：\(OpenStaffDateFormatter.displayString(from: endedAt))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                    .tag(session.sessionId as String?)
                                }
                            }
                            .listStyle(.inset)
                            .frame(minWidth: 260, minHeight: 280)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("任务列表")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if viewModel.tasksForSelectedSession.isEmpty {
                                Text("该会话暂无任务。")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(.top, 8)
                            } else {
                                List(
                                    selection: Binding(
                                        get: { viewModel.selectedLearningTaskId },
                                        set: { viewModel.selectLearningTask($0) }
                                    )
                                ) {
                                    ForEach(viewModel.tasksForSelectedSession) { task in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(task.taskId)
                                                .font(.callout)
                                            HStack(spacing: 6) {
                                                if let eventCount = task.eventCount {
                                                    Text("事件 \(eventCount)")
                                                }
                                                if let stepCount = task.knowledgeStepCount {
                                                    Text("步骤 \(stepCount)")
                                                }
                                                if let boundary = task.boundaryReason {
                                                    Text("边界 \(boundary)")
                                                }
                                            }
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 2)
                                        .tag(task.id as String?)
                                    }
                                }
                                .listStyle(.inset)
                            }
                        }
                        .frame(minWidth: 280, minHeight: 280)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("任务详情与知识条目")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let detail = viewModel.selectedTaskDetail {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 10) {
                                        LabeledContent("任务 ID", value: detail.task.taskId)
                                        LabeledContent("会话 ID", value: detail.task.sessionId)
                                        if let appName = detail.task.appName {
                                            LabeledContent("应用", value: appName)
                                        }
                                        if let startedAt = detail.task.startedAt {
                                            LabeledContent("开始时间", value: OpenStaffDateFormatter.displayString(from: startedAt))
                                        }
                                        if let endedAt = detail.task.endedAt {
                                            LabeledContent("结束时间", value: OpenStaffDateFormatter.displayString(from: endedAt))
                                        }
                                        if let boundaryReason = detail.task.boundaryReason {
                                            LabeledContent("切片边界", value: boundaryReason)
                                        }

                                        Divider()

                                        if let knowledge = detail.knowledgeItem {
                                            LabeledContent("知识条目 ID", value: knowledge.knowledgeItemId)
                                            LabeledContent("目标", value: knowledge.goal)
                                            LabeledContent("摘要", value: knowledge.summary)
                                            LabeledContent("上下文应用", value: knowledge.contextAppName)
                                            if let windowTitle = knowledge.windowTitle,
                                               !windowTitle.isEmpty {
                                                LabeledContent("窗口标题", value: windowTitle)
                                            }
                                            if let createdAt = knowledge.createdAt {
                                                LabeledContent("生成时间", value: OpenStaffDateFormatter.displayString(from: createdAt))
                                            }
                                            if !knowledge.constraints.isEmpty {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("约束")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                    ForEach(knowledge.constraints) { constraint in
                                                        Text("• [\(constraint.type)] \(constraint.description)")
                                                            .font(.caption)
                                                    }
                                                }
                                            }
                                            if !knowledge.steps.isEmpty {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("步骤")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                    ForEach(knowledge.steps) { step in
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text("\(step.stepId): \(step.instruction)")
                                                                .font(.caption)
                                                            if !step.sourceEventIds.isEmpty {
                                                                Text("source: \(step.sourceEventIds.joined(separator: ", "))")
                                                                    .font(.caption2)
                                                                    .foregroundStyle(.secondary)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        } else {
                                            Text("该任务暂无知识条目。")
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            } else {
                                Text("请选择一个任务查看详情。")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(.top, 8)
                            }
                        }
                        .frame(minWidth: 360, minHeight: 280)
                    }
                }
            }

                GroupBox("教学后处理（LLM / Skill）") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(
                            "转换方式",
                            selection: Binding(
                                get: { viewModel.teachingSkillGenerationMethod },
                                set: { viewModel.selectTeachingSkillGenerationMethod($0) }
                            )
                        ) {
                            ForEach(TeachingSkillGenerationMethod.allCases, id: \.self) { method in
                                Text(viewModel.teachingSkillGenerationMethodDisplayName(for: method)).tag(method)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(viewModel.teachingSkillProcessing)

                        if let target = viewModel.latestTeachingKnowledgeTarget {
                            Text("当前知识目标：\(target.knowledgeItemId) · \(target.taskId) · \(target.sessionId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("知识文件：\(target.knowledgeItemPath.path)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        } else {
                            Text("暂无可用知识目标。请先运行一次教学模式并停止。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        switch viewModel.teachingSkillGenerationMethod {
                        case .api:
                            HStack(spacing: 8) {
                                Button("执行自动 API 转换") {
                                    viewModel.runTeachingSkillGenerationWithAPI()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(viewModel.latestTeachingKnowledgeTarget == nil || viewModel.teachingSkillProcessing)

                                Text("将调用 ChatGPT API 自动完成：解析知识 -> 生成 OpenClaw Skill。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        case .manual:
                            HStack(spacing: 8) {
                                Button("生成提示词") {
                                    viewModel.prepareManualPromptForLatestKnowledge()
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.latestTeachingKnowledgeTarget == nil || viewModel.teachingSkillProcessing)

                                Button("复制提示词与数据") {
                                    viewModel.copyManualPromptPreviewToClipboard()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!viewModel.canCopyManualPromptPreview || viewModel.teachingSkillProcessing)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("提示词预览（复制后粘贴到 ChatGPT）")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextEditor(
                                    text: Binding(
                                        get: { viewModel.manualPromptPreviewText },
                                        set: { _ in }
                                    )
                                )
                                .font(.system(.caption, design: .monospaced))
                                .frame(minHeight: 190)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                )
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("LLM 结果输入（粘贴 ChatGPT 返回内容）")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextEditor(text: $viewModel.manualLLMResultInput)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(minHeight: 130)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                    )
                                Button("执行手动结果") {
                                    viewModel.executeManualTeachingResult()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!viewModel.canExecuteManualLLMResult || viewModel.teachingSkillProcessing)
                            }
                        }

                        if let skillPath = viewModel.latestGeneratedSkillDirectoryPath,
                           let skillName = viewModel.latestGeneratedSkillName {
                            Text("最近生成 Skill：\(skillName) @ \(skillPath)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if let llmOutputPath = viewModel.latestLLMOutputPath {
                            Text("最近 LLM 输出文件：\(llmOutputPath)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if let teachingSkillStatusMessage = viewModel.teachingSkillStatusMessage {
                            Text(teachingSkillStatusMessage)
                                .font(.caption)
                                .foregroundStyle(viewModel.teachingSkillStatusSucceeded ? .green : .red)
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("已学技能（运行 / 删除 / 审核）") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("当前执行后端：\(viewModel.executorBackendDescription)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if viewModel.usesHelperExecutorBackend {
                            if let helperPath = viewModel.executorHelperPath,
                               !helperPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("当前正在使用的 helper 路径：\(helperPath)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            } else {
                                Text("当前正在使用的 helper 路径：未激活（运行一次技能后显示）")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("权限要求：仅需为 OpenStaffApp 授予辅助功能权限。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if viewModel.learnedSkills.isEmpty {
                            Text("暂无已学技能。请先完成一次教学后处理（API 或手动粘贴执行）。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        } else {
                            Table(
                                viewModel.learnedSkills,
                                selection: Binding(
                                    get: { viewModel.selectedLearnedSkillId },
                                    set: { viewModel.selectLearnedSkill($0) }
                                )
                            ) {
                                TableColumn("技能名") { skill in
                                    Text(skill.skillName)
                                        .lineLimit(1)
                                }
                                TableColumn("任务") { skill in
                                    Text(skill.taskId)
                                        .lineLimit(1)
                                }
                                TableColumn("审核状态") { skill in
                                    Text(skill.reviewStatusText)
                                        .foregroundStyle(skill.isReviewed ? .green : .secondary)
                                }
                                TableColumn("预检") { skill in
                                    Text(skill.preflightStatusText)
                                        .foregroundStyle(preflightColor(for: skill.preflight.status))
                                }
                                TableColumn("来源") { skill in
                                    Text(skill.storageScopeDisplayName)
                                }
                                TableColumn("操作") { skill in
                                    HStack(spacing: 6) {
                                        Button("运行") {
                                            viewModel.runLearnedSkill(skill.id)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(
                                            viewModel.runningMode != .student
                                            || viewModel.skillActionProcessing
                                            || viewModel.emergencyStopActive
                                        )

                                        Button("删除") {
                                            viewModel.deleteLearnedSkill(skill.id)
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(viewModel.skillActionProcessing)

                                        Menu("审核") {
                                            Button("通过") {
                                                viewModel.reviewLearnedSkill(skill.id, decision: .approved)
                                            }
                                            Button("驳回") {
                                                viewModel.reviewLearnedSkill(skill.id, decision: .rejected)
                                            }
                                        }
                                        .disabled(viewModel.skillActionProcessing)
                                    }
                                }
                            }
                            .frame(minHeight: 260)

                            Text("运行说明：仅在学生模式运行中可执行“运行”。")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let selectedSkill = viewModel.selectedLearnedSkill {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("预检摘要：\(selectedSkill.preflight.summary)")
                                        .font(.caption)
                                        .foregroundStyle(preflightColor(for: selectedSkill.preflight.status))
                                        .textSelection(.enabled)

                                    if !selectedSkill.preflightIssueSummary.isEmpty {
                                        Text(selectedSkill.preflightIssueSummary)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }

                                    HStack(spacing: 8) {
                                        Button(viewModel.skillDriftProcessing ? "检测中..." : "检测漂移") {
                                            viewModel.detectSelectedSkillDrift()
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(viewModel.skillActionProcessing || viewModel.skillDriftProcessing)
                                    }

                                    if let driftReport = viewModel.selectedSkillDriftReport {
                                        Text("漂移诊断：\(driftReport.summary)")
                                            .font(.caption)
                                            .foregroundStyle(driftColor(for: driftReport.status))
                                            .textSelection(.enabled)

                                        ForEach(driftReport.findings.filter { $0.driftKind != .none }, id: \.stepId) { finding in
                                            Text("步骤 \(finding.stepId)：\(finding.driftKind.rawValue) · \(finding.message)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                        }
                                    }

                                    if let repairPlan = viewModel.selectedSkillRepairPlan,
                                       !repairPlan.actions.isEmpty {
                                        Text("修复建议：\(repairPlan.summary)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)

                                        if let preferenceDecision = repairPlan.preferenceDecision {
                                            Text("偏好装配：\(preferenceDecision.summary)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                        }

                                        ForEach(repairPlan.actions, id: \.actionId) { action in
                                            HStack(alignment: .top, spacing: 8) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(action.title)
                                                        .font(.caption)
                                                        .fontWeight(.semibold)
                                                    Text(action.description)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .textSelection(.enabled)
                                                    Text(action.reason)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .textSelection(.enabled)
                                                    if let preferenceReason = action.preferenceReason {
                                                        Text(preferenceReason)
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                            .textSelection(.enabled)
                                                    }
                                                    if let appliedRuleIds = action.appliedRuleIds,
                                                       !appliedRuleIds.isEmpty {
                                                        Text("规则来源：\(appliedRuleIds.joined(separator: "、"))")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                            .textSelection(.enabled)
                                                    }
                                                }
                                                Spacer()
                                                Button(action.type.buttonTitle) {
                                                    viewModel.recordSelectedSkillRepairAction(action.actionId)
                                                }
                                                .buttonStyle(.bordered)
                                                .disabled(viewModel.skillActionProcessing || viewModel.skillDriftProcessing)
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if let skillActionStatusMessage = viewModel.skillActionStatusMessage {
                            Text(skillActionStatusMessage)
                                .font(.caption)
                                .foregroundStyle(viewModel.skillActionSucceeded ? .green : .red)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("审阅与反馈") {
                if viewModel.executionLogs.isEmpty {
                    Text("暂无执行日志。可先运行 assist/student 流程后刷新。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("执行日志")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            List(
                                selection: Binding(
                                    get: { viewModel.selectedExecutionLogId },
                                    set: { viewModel.selectExecutionLog($0) }
                                )
                            ) {
                                ForEach(viewModel.executionLogs) { log in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(viewModel.modeDisplayName(for: log.mode))
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(log.mode.color)
                                            Text(log.status)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(log.message)
                                            .font(.callout)
                                            .lineLimit(2)
                                        Text("\(log.sessionId) · \(log.taskId ?? "no-task") · \(OpenStaffDateFormatter.displayString(from: log.timestamp))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                    .tag(log.id as String?)
                                }
                            }
                            .listStyle(.inset)
                            .frame(minWidth: 360, minHeight: 260)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("日志详情与老师反馈")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let log = viewModel.selectedExecutionLog {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 10) {
                                        LabeledContent("时间", value: OpenStaffDateFormatter.displayString(from: log.timestamp))
                                        LabeledContent("会话 ID", value: log.sessionId)
                                        LabeledContent("任务 ID", value: log.taskId ?? "no-task")
                                        LabeledContent("状态码", value: log.status)
                                        if let component = log.component {
                                            LabeledContent("组件", value: component)
                                        }
                                        if let errorCode = log.errorCode {
                                            LabeledContent("错误码", value: errorCode)
                                        }
                                        LabeledContent("日志位置", value: "\(log.sourceFilePath):\(log.lineNumber)")
                                        if let detail = viewModel.selectedExecutionReviewDetail {
                                            if let goal = detail.goal, !goal.isEmpty {
                                                LabeledContent("目标", value: goal)
                                            }
                                            if let skillName = detail.skillName {
                                                LabeledContent("当前 skill", value: skillName)
                                            }
                                            if let knowledgeItemId = detail.knowledgeItemId {
                                                LabeledContent("知识条目", value: knowledgeItemId)
                                            }
                                            if let repairVersion = detail.currentRepairVersion {
                                                LabeledContent("repairVersion", value: "\(repairVersion)")
                                            }
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("消息")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(log.message)
                                                .font(.callout)
                                        }

                                        if let detail = viewModel.selectedExecutionReviewDetail {
                                            Divider()

                                            VStack(alignment: .leading, spacing: 8) {
                                                Text("三栏对照")
                                                    .font(.headline)
                                                if let knowledgeSummary = detail.knowledgeSummary,
                                                   !knowledgeSummary.isEmpty {
                                                    Text(knowledgeSummary)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }

                                                if detail.comparisonRows.isEmpty {
                                                    Text("当前日志尚未关联到结构化步骤对照。")
                                                        .font(.callout)
                                                        .foregroundStyle(.secondary)
                                                } else {
                                                    ExecutionReviewComparisonBoard(rows: detail.comparisonRows)
                                                }
                                            }
                                        }

                                        Divider()

                                        if let feedback = viewModel.latestFeedbackForSelectedLog {
                                            LabeledContent("最近反馈", value: feedback.decision.displayName)
                                            if let note = feedback.note, !note.isEmpty {
                                                LabeledContent("反馈备注", value: note)
                                            }
                                            LabeledContent("反馈时间", value: OpenStaffDateFormatter.displayString(from: feedback.timestamp))
                                        } else {
                                            Text("该日志暂无老师反馈。")
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                        }

                                        if let detail = viewModel.selectedExecutionReviewDetail,
                                           !detail.reviewSuggestions.isEmpty {
                                            Divider()

                                            VStack(alignment: .leading, spacing: 6) {
                                                Text("偏好化审阅建议")
                                                    .font(.headline)
                                                Text("只做建议排序，不会替老师自动做决定。")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)

                                                if let decision = detail.reviewPreferenceDecision {
                                                    Text(decision.summary)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .textSelection(.enabled)
                                                }

                                                ExecutionReviewSuggestionList(
                                                    suggestions: detail.reviewSuggestions,
                                                    applySuggestedNote: { note in
                                                        viewModel.quickFeedbackNoteInput = note
                                                    }
                                                )
                                            }
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Quick Feedback Bar")
                                                .font(.headline)
                                            Text("固定 7 个快评动作，可选补一句短备注。")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            TeacherQuickFeedbackBar(
                                                actions: viewModel.quickFeedbackActions,
                                                note: $viewModel.quickFeedbackNoteInput,
                                                statusMessage: viewModel.quickFeedbackStatusMessage,
                                                statusSucceeded: viewModel.quickFeedbackWriteSucceeded,
                                                disabledReason: viewModel.quickFeedbackDisabledReason(for:),
                                                onSubmit: viewModel.submitTeacherFeedback(decision:)
                                            )
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            } else {
                                Text("请选择一条执行日志进行审阅。")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(.top, 8)
                            }
                        }
                        .frame(minWidth: 520, minHeight: 260)
                    }
                }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 920, minHeight: 640)
        .task {
            viewModel.startSafetyControlsIfNeeded()
            viewModel.refreshDashboard(promptAccessibilityPermission: false)
        }
    }
}

private func preflightColor(for status: SkillPreflightStatus) -> Color {
    switch status {
    case .passed:
        return .green
    case .needsTeacherConfirmation:
        return .orange
    case .failed:
        return .red
    }
}

private func driftColor(for status: SkillDriftStatus) -> Color {
    switch status {
    case .stable:
        return .green
    case .driftDetected:
        return .orange
    }
}

private func executionResultColor(for status: ExecutionReviewResultStatus) -> Color {
    switch status {
    case .succeeded:
        return .green
    case .failed:
        return .red
    case .blocked:
        return .orange
    case .unknown:
        return .secondary
    }
}

private func reviewSuggestionTintColor(for action: TeacherQuickFeedbackAction) -> Color {
    switch action {
    case .approved:
        return Color(red: 0.16, green: 0.56, blue: 0.28)
    case .rejected:
        return Color(red: 0.47, green: 0.47, blue: 0.50)
    case .needsRevision, .fixLocator, .reteach:
        return Color(red: 0.07, green: 0.40, blue: 0.82)
    case .tooDangerous:
        return Color(red: 0.75, green: 0.15, blue: 0.12)
    case .wrongOrder:
        return Color(red: 0.88, green: 0.47, blue: 0.10)
    case .wrongStyle:
        return Color(red: 0.62, green: 0.35, blue: 0.13)
    }
}

private struct ExecutionReviewComparisonBoard: View {
    let rows: [ExecutionReviewComparisonRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 180), alignment: .topLeading),
                    GridItem(.flexible(minimum: 180), alignment: .topLeading),
                    GridItem(.flexible(minimum: 180), alignment: .topLeading)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                header("老师原始步骤")
                header("当前 skill 步骤")
                header("本次实际执行结果")

                ForEach(rows) { row in
                    ExecutionReviewColumnCard(
                        badge: "#\(row.order)",
                        item: row.teacherStep
                    )
                    ExecutionReviewColumnCard(
                        badge: row.skillStepId ?? "#\(row.order)",
                        item: row.skillStep
                    )
                    ExecutionReviewColumnCard(
                        badge: row.actualResult.title,
                        item: row.actualResult,
                        accentColor: executionResultColor(for: row.resultStatus)
                    )
                }
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct ExecutionReviewColumnCard: View {
    let badge: String
    let item: ExecutionReviewColumnItem
    var accentColor: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(badge)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(accentColor)
            Text(item.title)
                .font(.callout.weight(.semibold))
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accentColor.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct ExecutionReviewSuggestionList: View {
    let suggestions: [ExecutionReviewSuggestion]
    let applySuggestedNote: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(suggestions.prefix(3)) { suggestion in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(suggestion.action.displayName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(reviewSuggestionTintColor(for: suggestion.action).opacity(0.14))
                            )
                        Text(String(format: "priority %.2f", suggestion.priority))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let suggestedNote = suggestion.suggestedNote, !suggestedNote.isEmpty {
                            Button("填入短备注") {
                                applySuggestedNote(suggestedNote)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                        }
                    }

                    Text(suggestion.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let suggestedNote = suggestion.suggestedNote, !suggestedNote.isEmpty {
                        Text("建议短备注：\(suggestedNote)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if !suggestion.appliedRuleIds.isEmpty {
                        Text("规则来源：\(suggestion.appliedRuleIds.joined(separator: "、"))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(reviewSuggestionTintColor(for: suggestion.action).opacity(0.18), lineWidth: 1)
                )
            }
        }
    }
}

struct PermissionRow: View {
    let title: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(granted ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text(granted ? "已授权" : "未授权")
                .foregroundStyle(granted ? .green : .red)
        }
        .font(.callout)
    }
}

enum EmergencyStopSource {
    case uiButton
    case globalHotkey

    var displayName: String {
        switch self {
        case .uiButton:
            return "UI按钮"
        case .globalHotkey:
            return "全局快捷键"
        }
    }
}

enum TeachingSkillGenerationMethod: String, CaseIterable {
    case api
    case manual
}

struct TeachingKnowledgeTarget {
    let sessionId: String
    let taskId: String
    let knowledgeItemId: String
    let knowledgeItemPath: URL
}

final class EmergencyStopHotkeyMonitor {
    private let handler: () -> Void
    private var globalMonitorToken: Any?
    private var localMonitorToken: Any?

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func start() {
        guard globalMonitorToken == nil, localMonitorToken == nil else {
            return
        }

        globalMonitorToken = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return
            }
            if self.isEmergencyStopShortcut(event: event) {
                self.handler()
            }
        }

        localMonitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }
            if self.isEmergencyStopShortcut(event: event) {
                self.handler()
                return nil
            }
            return event
        }
    }

    func stop() {
        if let globalMonitorToken {
            NSEvent.removeMonitor(globalMonitorToken)
            self.globalMonitorToken = nil
        }
        if let localMonitorToken {
            NSEvent.removeMonitor(localMonitorToken)
            self.localMonitorToken = nil
        }
    }

    private func isEmergencyStopShortcut(event: NSEvent) -> Bool {
        let requiredFlags: NSEvent.ModifierFlags = [.command, .shift]
        let modifiersMatch = event.modifierFlags.intersection(requiredFlags) == requiredFlags
        guard modifiersMatch else {
            return false
        }

        let character = event.charactersIgnoringModifiers ?? ""
        if character == "." {
            return true
        }

        return event.keyCode == 47
    }
}

@MainActor
final class OpenStaffDashboardViewModel: ObservableObject {
    @Published var currentMode: OpenStaffMode
    @Published var selectedMode: OpenStaffMode
    @Published private(set) var runningMode: OpenStaffMode?
    @Published private(set) var learningSessionState: LearningSessionState
    @Published var guardInputs = ModeGuardInput()
    @Published private(set) var transitionMessage: String?
    @Published private(set) var lastDecision: ModeTransitionDecision?
    @Published private(set) var permissionSnapshot: PermissionSnapshot
    @Published private(set) var recentTasks: [RecentTaskSummary]
    @Published private(set) var learningSessions: [LearningSessionSummary]
    @Published var selectedLearningSessionId: String?
    @Published var selectedLearningTaskId: String?
    @Published private(set) var executionLogs: [ExecutionLogSummary]
    @Published var selectedExecutionLogId: String?
    @Published var quickFeedbackNoteInput = ""
    @Published private(set) var latestFeedbackForSelectedLog: TeacherFeedbackSummary?
    @Published private(set) var selectedExecutionReviewDetail: ExecutionReviewDetail?
    @Published private(set) var quickFeedbackStatusMessage: String?
    @Published private(set) var quickFeedbackWriteSucceeded = false
    @Published private(set) var emergencyStopActive = false
    @Published private(set) var emergencyStopActivatedAt: Date?
    @Published private(set) var emergencyStopSource: EmergencyStopSource?
    @Published private(set) var lastRefreshedAt: Date?
    @Published private(set) var activeObservationSessionId: String?
    @Published private(set) var capturedEventCount = 0
    @Published var teachingSkillGenerationMethod: TeachingSkillGenerationMethod = .manual
    @Published private(set) var latestTeachingKnowledgeTarget: TeachingKnowledgeTarget?
    @Published private(set) var manualPromptPreviewText = ""
    @Published var manualLLMResultInput = ""
    @Published private(set) var teachingSkillStatusMessage: String?
    @Published private(set) var teachingSkillStatusSucceeded = true
    @Published private(set) var teachingSkillProcessing = false
    @Published private(set) var latestGeneratedSkillDirectoryPath: String?
    @Published private(set) var latestGeneratedSkillName: String?
    @Published private(set) var latestLLMOutputPath: String?
    @Published private(set) var learnedSkills: [LearnedSkillSummary]
    @Published var selectedLearnedSkillId: String?
    @Published private(set) var selectedLearnedSkillReview: LearnedSkillReviewSummary?
    @Published private(set) var skillActionStatusMessage: String?
    @Published private(set) var skillActionSucceeded = true
    @Published private(set) var skillActionProcessing = false
    @Published private(set) var selectedSkillDriftReport: SkillDriftReport?
    @Published private(set) var selectedSkillRepairPlan: SkillRepairPlan?
    @Published private(set) var skillDriftProcessing = false
    @Published private(set) var executorBackendDescription: String
    @Published private(set) var usesHelperExecutorBackend: Bool
    @Published private(set) var executorHelperPath: String?
    @Published private(set) var learningPrivacyConfiguration: LearningPrivacyConfiguration
    @Published private(set) var learningPrivacyConfigurationPath: String
    @Published private(set) var learningPrivacyStatusMessage: String?
    @Published private(set) var learningPrivacyStatusSucceeded = true

    private let logger = InMemoryOrchestratorStateLogger()
    private let stateMachine: ModeStateMachine
    private let sessionId: String
    private let permissionSnapshotProvider: (Bool) -> PermissionSnapshot
    private var traceSequence = 0
    private var learningSnapshot = LearningSnapshot.empty
    private var executionReviewSnapshot = ExecutionReviewSnapshot.empty
    private var learnedSkillSnapshot = LearnedSkillSnapshot.empty
    private var safetyControlsStarted = false
    private var integratedWorkflowTask: Task<Void, Never>?
    private let modeObservationCapture: any ModeObservationCaptureControlling
    private let learningContextSnapshotProvider: any LearningContextSnapshotProviding
    private let learningLastSuccessfulWriteProvider: any LearningLastSuccessfulWriteProviding
    private let learningPrivacyConfigurationStore: any LearningPrivacyConfigurationStoring
    private let learningSensitiveScenePolicy: SensitiveScenePolicy
    private let nowProvider: () -> Date
    private var learningStatusRefreshTimer: Timer?
    private var learningStatusRefreshTimerTarget: DashboardLearningStatusRefreshTimerTarget?
    private var latestLearningContextSnapshot = ContextSnapshot(
        appName: "Unknown",
        appBundleId: "unknown.bundle.id",
        windowTitle: nil,
        windowId: nil
    )
    private var lastSuccessfulLearningWriteAt: Date?
    private var capturedEventBaseCount = 0
    private var ignoreNextObservationResetCount = false
    private lazy var executionReviewStore = ExecutionReviewStore(
        logsRootDirectory: OpenStaffWorkspacePaths.logsDirectory,
        feedbackRootDirectory: OpenStaffWorkspacePaths.feedbackDirectory,
        reportsRootDirectory: OpenStaffWorkspacePaths.reportsDirectory,
        knowledgeRootDirectory: OpenStaffWorkspacePaths.knowledgeDirectory,
        preferencesRootDirectory: OpenStaffWorkspacePaths.preferencesDirectory,
        skillRoots: [
            ExecutionReviewSkillRoot(
                scopeId: LearnedSkillStorageScope.pending.rawValue,
                directory: OpenStaffWorkspacePaths.skillsPendingDirectory
            ),
            ExecutionReviewSkillRoot(
                scopeId: LearnedSkillStorageScope.done.rawValue,
                directory: OpenStaffWorkspacePaths.skillsDoneDirectory
            )
        ]
    )
    private lazy var emergencyStopHotkeyMonitor = EmergencyStopHotkeyMonitor { [weak self] in
        DispatchQueue.main.async { [weak self] in
            self?.activateEmergencyStop(source: .globalHotkey)
        }
    }

    init(
        initialMode: OpenStaffMode = .teaching,
        modeObservationCapture: any ModeObservationCaptureControlling = ModeObservationCaptureService(),
        permissionSnapshotProvider: @escaping (Bool) -> PermissionSnapshot = PermissionSnapshot.capture,
        learningContextSnapshotProvider: any LearningContextSnapshotProviding = SystemLearningContextSnapshotProvider(),
        learningLastSuccessfulWriteProvider: any LearningLastSuccessfulWriteProviding = RawEventLastSuccessfulWriteProvider(),
        learningPrivacyConfigurationStore: any LearningPrivacyConfigurationStoring = FileLearningPrivacyConfigurationStore(),
        learningSensitiveScenePolicy: SensitiveScenePolicy = SensitiveScenePolicy(),
        nowProvider: @escaping () -> Date = Date.init
    ) {
        let loadedLearningPrivacyConfiguration = learningPrivacyConfigurationStore
            .load()
            .normalized(referenceDate: nowProvider())
        self.currentMode = initialMode
        self.selectedMode = initialMode
        self.runningMode = nil
        self.permissionSnapshot = .unknown
        self.recentTasks = []
        self.learningSessions = []
        self.executionLogs = []
        self.selectedExecutionReviewDetail = nil
        self.learnedSkills = []
        self.selectedSkillDriftReport = nil
        self.selectedSkillRepairPlan = nil
        let backend = OpenStaffActionExecutor.backend
        self.executorBackendDescription = backend.displayName
        self.usesHelperExecutorBackend = backend == .helper
        if backend == .helper {
            self.executorHelperPath = OpenStaffExecutorXPCClient.shared.currentHelperExecutablePath()
        } else {
            self.executorHelperPath = nil
        }
        self.learningPrivacyConfiguration = loadedLearningPrivacyConfiguration
        self.learningPrivacyConfigurationPath = learningPrivacyConfigurationStore.configurationURL.path
        self.learningPrivacyStatusMessage = nil
        self.activeObservationSessionId = nil
        self.modeObservationCapture = modeObservationCapture
        self.permissionSnapshotProvider = permissionSnapshotProvider
        self.learningContextSnapshotProvider = learningContextSnapshotProvider
        self.learningLastSuccessfulWriteProvider = learningLastSuccessfulWriteProvider
        self.learningPrivacyConfigurationStore = learningPrivacyConfigurationStore
        self.learningSensitiveScenePolicy = learningSensitiveScenePolicy
        self.nowProvider = nowProvider
        self.stateMachine = ModeStateMachine(initialMode: initialMode, logger: logger)
        self.sessionId = "session-gui-\(UUID().uuidString.prefix(8).lowercased())"
        self.lastSuccessfulLearningWriteAt = learningLastSuccessfulWriteProvider.latestSuccessfulWriteAt(
            rawEventsRootDirectory: OpenStaffWorkspacePaths.rawEventsDirectory
        )
        self.learningSessionState = LearningSessionState.initial(
            selectedMode: initialMode,
            lastSuccessfulWriteAt: self.lastSuccessfulLearningWriteAt,
            updatedAt: nowProvider()
        )

        self.modeObservationCapture.onFatalError = { [weak self] error in
            DispatchQueue.main.async { [weak self] in
                self?.handleObservationCaptureFailure(error)
            }
        }
        self.modeObservationCapture.onEventCaptured = { [weak self] count in
            DispatchQueue.main.async { [weak self] in
                self?.handleCapturedEventCountUpdate(count)
            }
        }
    }

    var isAnyModeRunning: Bool {
        runningMode != nil
    }

    var learningPauseResumeActionTitle: String {
        learningSessionState.isUserPauseActive ? "恢复学习" : "暂停学习"
    }

    var canToggleLearningPauseResume: Bool {
        learningSessionState.canPauseOrResumeInOneClick
    }

    var learningAppExclusions: [LearningPrivacyAppExclusion] {
        learningPrivacyConfiguration.excludedApps
    }

    var learningWindowTitleExclusions: [LearningWindowTitleExclusionRule] {
        learningPrivacyConfiguration.excludedWindowTitleRules
    }

    var learningSensitiveSceneRules: [SensitiveSceneRule] {
        learningSensitiveScenePolicy.rules
    }

    var learningTemporaryPauseDescription: String {
        guard let temporaryPauseUntil = learningPrivacyConfiguration.temporaryPauseUntil,
              temporaryPauseUntil > nowProvider() else {
            return "当前未启用临时暂停。"
        }
        return "已暂停至 \(OpenStaffDateFormatter.displayString(from: temporaryPauseUntil))。"
    }

    var modeStatusSummary: String {
        if let runningMode {
            return "\(modeDisplayName(for: runningMode))（运行中）"
        }
        return "待机（已选择\(modeDisplayName(for: selectedMode))）"
    }

    var lastTransitionAccepted: Bool {
        lastDecision?.accepted ?? true
    }

    var currentStatusCode: String {
        if let lastDecision {
            return lastDecision.status.rawValue
        }
        return OrchestratorStatusCode.modeStable.rawValue
    }

    var currentCapabilities: [String] {
        let mode = runningMode ?? selectedMode
        return stateMachine.allowedCapabilities(for: mode).map(\.rawValue).sorted()
    }

    var unmetRequirementsText: String {
        guard let lastDecision, !lastDecision.unmetRequirements.isEmpty else {
            return ""
        }
        return lastDecision.unmetRequirements.map(\.rawValue).joined(separator: ", ")
    }

    var captureStatusText: String? {
        guard let runningMode, shouldObserveTeacherActions(for: runningMode) else {
            return nil
        }
        let sessionLabel = activeObservationSessionId ?? sessionId
        return "采集会话：\(sessionLabel) · 原始事件：\(capturedEventCount)"
    }

    var orchestratorLogEntries: [OrchestratorLogEntry] {
        Array(logger.entries.reversed())
    }

    var debugDiagnosticsInput: DashboardDebugDiagnosticsInput {
        DashboardDebugDiagnosticsInput(
            selectedMode: selectedMode,
            currentMode: currentMode,
            runningMode: runningMode,
            modeStatusSummary: modeStatusSummary,
            currentStatusCode: currentStatusCode,
            transitionMessage: transitionMessage,
            transitionAccepted: lastDecision?.accepted,
            unmetRequirements: lastDecision?.unmetRequirements ?? [],
            permissionSnapshot: permissionSnapshot,
            captureStatusText: captureStatusText,
            activeObservationSessionId: activeObservationSessionId,
            capturedEventCount: capturedEventCount,
            learningSessionState: learningSessionState,
            quickFeedbackStatusMessage: quickFeedbackStatusMessage,
            quickFeedbackSucceeded: quickFeedbackWriteSucceeded,
            teachingSkillStatusMessage: teachingSkillStatusMessage,
            teachingSkillStatusSucceeded: teachingSkillStatusSucceeded,
            teachingSkillProcessing: teachingSkillProcessing,
            skillActionStatusMessage: skillActionStatusMessage,
            skillActionSucceeded: skillActionSucceeded,
            skillActionProcessing: skillActionProcessing,
            learningPrivacyStatusMessage: learningPrivacyStatusMessage,
            learningPrivacyStatusSucceeded: learningPrivacyStatusSucceeded,
            executorBackendDescription: executorBackendDescription,
            usesHelperExecutorBackend: usesHelperExecutorBackend,
            executorHelperPath: executorHelperPath,
            isObservationCaptureRunning: modeObservationCapture.isRunning,
            currentCapabilities: currentCapabilities,
            selectedExecutionLog: selectedExecutionLog,
            selectedExecutionReviewDetail: selectedExecutionReviewDetail,
            selectedLearnedSkill: selectedLearnedSkill,
            selectedSkillDriftReport: selectedSkillDriftReport,
            selectedSkillRepairPlan: selectedSkillRepairPlan
        )
    }

    func toggleLearningPauseResume() {
        guard canToggleLearningPauseResume else {
            return
        }

        if learningSessionState.isUserPauseActive {
            resumeLearningCapture()
        } else {
            pauseLearningCapture()
        }
    }

    var tasksForSelectedSession: [LearningTaskSummary] {
        guard let selectedLearningSessionId else {
            return []
        }
        return learningSnapshot.tasksBySession[selectedLearningSessionId] ?? []
    }

    var selectedTaskDetail: LearningTaskDetail? {
        guard let selectedLearningTaskId else {
            return nil
        }
        return learningSnapshot.taskDetailsById[selectedLearningTaskId]
    }

    var selectedExecutionLog: ExecutionLogSummary? {
        guard let selectedExecutionLogId else {
            return nil
        }
        return executionReviewSnapshot.logById[selectedExecutionLogId]
    }

    var quickFeedbackActions: [TeacherQuickFeedbackAction] {
        TeacherQuickFeedbackAction.quickActions
    }

    var selectedLearnedSkill: LearnedSkillSummary? {
        guard let selectedLearnedSkillId else {
            return nil
        }
        return learnedSkillSnapshot.skillsById[selectedLearnedSkillId]
    }

    var emergencyStopStatusText: String {
        guard emergencyStopActive else {
            return "紧急停止：未激活（全局快捷键 Cmd+Shift+.）"
        }

        let activatedAt = emergencyStopActivatedAt.map(OpenStaffDateFormatter.displayString(from:)) ?? "unknown-time"
        let sourceText = emergencyStopSource?.displayName ?? "unknown-source"
        return "紧急停止：已激活（\(sourceText) @ \(activatedAt)）"
    }

    var canCopyManualPromptPreview: Bool {
        !manualPromptPreviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canExecuteManualLLMResult: Bool {
        guard latestTeachingKnowledgeTarget != nil else {
            return false
        }
        return !manualLLMResultInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func teachingSkillGenerationMethodDisplayName(for method: TeachingSkillGenerationMethod) -> String {
        switch method {
        case .api:
            return "自动 API"
        case .manual:
            return "手动粘贴"
        }
    }

    func modeDisplayName(for mode: OpenStaffMode) -> String {
        switch mode {
        case .teaching:
            return "教学模式"
        case .assist:
            return "辅助模式"
        case .student:
            return "学生模式"
        }
    }

    func requestModeChange(to targetMode: OpenStaffMode) {
        guard targetMode != currentMode else {
            return
        }

        traceSequence += 1
        let timestamp = OpenStaffDateFormatter.iso8601String(from: Date())
        let context = ModeTransitionContext(
            traceId: "trace-gui-\(traceSequence)",
            sessionId: sessionId,
            timestamp: timestamp,
            teacherConfirmed: guardInputs.teacherConfirmed,
            learnedKnowledgeReady: guardInputs.learnedKnowledgeReady,
            executionPlanReady: guardInputs.executionPlanReady,
            pendingAssistSuggestion: guardInputs.pendingAssistSuggestion,
            emergencyStopActive: guardInputs.emergencyStopActive
        )
        let decision = stateMachine.transition(to: targetMode, context: context)
        lastDecision = decision
        currentMode = stateMachine.currentMode
        if decision.accepted {
            selectedMode = currentMode
        }
        transitionMessage = decision.message
    }

    func selectMode(_ mode: OpenStaffMode) {
        selectedMode = mode
    }

    func selectTeachingSkillGenerationMethod(_ method: TeachingSkillGenerationMethod) {
        teachingSkillGenerationMethod = method
        if method == .manual,
           let target = latestTeachingKnowledgeTarget,
           manualPromptPreviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !teachingSkillProcessing {
            runManualPromptRender(for: target)
        }
    }

    func prepareManualPromptForLatestKnowledge() {
        guard let target = latestTeachingKnowledgeTarget else {
            teachingSkillStatusSucceeded = false
            teachingSkillStatusMessage = "暂无可用知识条目，请先完成一次教学模式并停止。"
            return
        }
        runManualPromptRender(for: target)
    }

    func runTeachingSkillGenerationWithAPI() {
        guard let target = latestTeachingKnowledgeTarget else {
            teachingSkillStatusSucceeded = false
            teachingSkillStatusMessage = "暂无可用知识条目，请先完成一次教学模式并停止。"
            return
        }
        runOpenAIAdapterSkillGeneration(for: target)
    }

    func executeManualTeachingResult() {
        guard let target = latestTeachingKnowledgeTarget else {
            teachingSkillStatusSucceeded = false
            teachingSkillStatusMessage = "暂无可执行的知识条目。"
            return
        }

        let normalized = manualLLMResultInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            teachingSkillStatusSucceeded = false
            teachingSkillStatusMessage = "请先粘贴 ChatGPT 返回的 JSON 结果。"
            return
        }

        runManualSkillGeneration(for: target, manualOutputText: normalized)
    }

    func copyManualPromptPreviewToClipboard() {
        let normalized = manualPromptPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            teachingSkillStatusSucceeded = false
            teachingSkillStatusMessage = "提示词预览为空，无法复制。"
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(normalized, forType: .string)
        teachingSkillStatusSucceeded = true
        teachingSkillStatusMessage = "提示词与必要数据已复制，可粘贴到 ChatGPT。"
    }

    func isModeRunning(_ mode: OpenStaffMode) -> Bool {
        runningMode == mode
    }

    func canToggleMode(_ mode: OpenStaffMode) -> Bool {
        guard let runningMode else {
            return true
        }
        return runningMode == mode
    }

    func pauseLearningCapture() {
        guard canToggleLearningPauseResume else {
            return
        }
        refreshLearningStatusSurface(forceTeacherPaused: true)
    }

    func resumeLearningCapture() {
        guard canToggleLearningPauseResume else {
            return
        }
        clearLearningTemporaryPause(announceResult: false)
        refreshLearningStatusSurface(forceTeacherPaused: false)
    }

    func reloadLearningPrivacyConfiguration() {
        learningPrivacyConfiguration = learningPrivacyConfigurationStore
            .load()
            .normalized(referenceDate: nowProvider())
        learningPrivacyStatusSucceeded = true
        learningPrivacyStatusMessage = "已重新加载隐私与排除规则。"
        refreshLearningStatusSurface()
    }

    func pauseLearningCaptureForFifteenMinutes() {
        updateLearningPrivacyConfiguration(
            successMessage: "学习已临时暂停 15 分钟。"
        ) { configuration in
            configuration.temporaryPauseUntil = nowProvider()
                .addingTimeInterval(LearningPrivacyConfiguration.temporaryPauseDuration)
        }
    }

    func clearLearningTemporaryPause(announceResult: Bool = true) {
        updateLearningPrivacyConfiguration(
            successMessage: announceResult ? "已取消临时暂停。" : nil,
            announceResult: announceResult
        ) { configuration in
            configuration.temporaryPauseUntil = nil
        }
    }

    func addCurrentAppToLearningExclusions() {
        let currentApp = learningSessionState.currentApp
        addLearningAppExclusion(
            displayName: currentApp.appName,
            bundleId: currentApp.appBundleId,
            appName: currentApp.appName
        )
    }

    func addLearningAppExclusion(
        displayName: String,
        bundleId: String,
        appName: String
    ) {
        let normalizedBundleId = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBundleId.isEmpty || !normalizedAppName.isEmpty else {
            learningPrivacyStatusSucceeded = false
            learningPrivacyStatusMessage = "请至少填写 bundle id 或 app 名称。"
            return
        }

        updateLearningPrivacyConfiguration(
            successMessage: "已添加 app 排除规则。"
        ) { configuration in
            configuration.excludedApps.append(
                LearningPrivacyAppExclusion(
                    displayName: normalizedDisplayName,
                    bundleId: normalizedBundleId,
                    appName: normalizedAppName
                )
            )
        }
    }

    func removeLearningAppExclusion(id: String) {
        updateLearningPrivacyConfiguration(
            successMessage: "已移除 app 排除规则。"
        ) { configuration in
            configuration.excludedApps.removeAll { $0.id == id }
        }
    }

    func addCurrentWindowTitleToLearningExclusions(
        matchType: LearningWindowTitleMatchType = .contains
    ) {
        let currentWindowTitle = learningSessionState.currentApp.windowTitle ?? ""
        addLearningWindowTitleExclusion(
            displayName: "",
            pattern: currentWindowTitle,
            matchType: matchType
        )
    }

    func addLearningWindowTitleExclusion(
        displayName: String,
        pattern: String,
        matchType: LearningWindowTitleMatchType
    ) {
        let normalizedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPattern.isEmpty else {
            learningPrivacyStatusSucceeded = false
            learningPrivacyStatusMessage = "窗口标题规则不能为空。"
            return
        }

        updateLearningPrivacyConfiguration(
            successMessage: "已添加窗口标题排除规则。"
        ) { configuration in
            configuration.excludedWindowTitleRules.append(
                LearningWindowTitleExclusionRule(
                    displayName: normalizedDisplayName,
                    pattern: normalizedPattern,
                    matchType: matchType
                )
            )
        }
    }

    func removeLearningWindowTitleExclusion(id: String) {
        updateLearningPrivacyConfiguration(
            successMessage: "已移除窗口标题排除规则。"
        ) { configuration in
            configuration.excludedWindowTitleRules.removeAll { $0.id == id }
        }
    }

    func setSensitiveSceneAutoMuteEnabled(_ enabled: Bool) {
        updateLearningPrivacyConfiguration(
            successMessage: enabled ? "已启用敏感场景自动静默。" : "已关闭敏感场景自动静默。"
        ) { configuration in
            configuration.sensitiveSceneAutoMuteEnabled = enabled
        }
    }

    func setSensitiveSceneRule(_ ruleId: String, enabled: Bool) {
        updateLearningPrivacyConfiguration(
            successMessage: enabled ? "已启用敏感场景规则。" : "已关闭敏感场景规则。"
        ) { configuration in
            let normalizedRuleId = ruleId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            configuration.enabledSensitiveSceneRuleIds.removeAll {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedRuleId
            }
            if enabled {
                configuration.enabledSensitiveSceneRuleIds.append(normalizedRuleId)
            }
        }
    }

    func startMode(_ mode: OpenStaffMode) {
        if let runningMode {
            if runningMode == mode {
                applySyntheticDecision(
                    fromMode: mode,
                    toMode: mode,
                    accepted: true,
                    status: .modeStable,
                    message: "\(modeDisplayName(for: mode))已在运行。"
                )
                return
            }

            applySyntheticDecision(
                fromMode: runningMode,
                toMode: mode,
                accepted: false,
                status: .modeTransitionRejected,
                errorCode: .transitionDenied,
                message: "\(modeDisplayName(for: runningMode))正在运行，请先停止后再启动\(modeDisplayName(for: mode))。"
            )
            return
        }

        if emergencyStopActive || guardInputs.emergencyStopActive {
            applySyntheticDecision(
                fromMode: currentMode,
                toMode: mode,
                accepted: false,
                status: .modeTransitionRejected,
                errorCode: .guardConditionFailed,
                message: "紧急停止已激活，请先解除后再启动\(modeDisplayName(for: mode))。"
            )
            return
        }

        selectedMode = mode
        if currentMode != mode {
            let previousMode = currentMode
            stateMachine.setCurrentMode(mode)
            currentMode = mode
            applySyntheticDecision(
                fromMode: previousMode,
                toMode: mode,
                accepted: true,
                status: .modeTransitionAccepted,
                message: "空闲态已直接切换到\(modeDisplayName(for: mode))并开始运行。"
            )
        } else {
            applySyntheticDecision(
                fromMode: mode,
                toMode: mode,
                accepted: true,
                status: .modeStable,
                message: "\(modeDisplayName(for: mode))已开始运行。"
            )
        }

        runningMode = mode
        capturedEventBaseCount = 0
        capturedEventCount = 0
        do {
            try startObservationCaptureIfNeeded(for: mode)
        } catch {
            runningMode = nil
            applySyntheticDecision(
                fromMode: mode,
                toMode: mode,
                accepted: false,
                status: .modeTransitionRejected,
                errorCode: .guardConditionFailed,
                message: "\(modeDisplayName(for: mode))启动失败：\(error.localizedDescription)"
            )
            return
        }

        if transitionMessage == nil {
            transitionMessage = "\(modeDisplayName(for: mode))已开始运行。"
        }
        refreshLearningStatusSurface()
        startIntegratedWorkflowIfNeeded(for: mode)
    }

    func stopMode(_ mode: OpenStaffMode) {
        guard runningMode == mode else {
            applySyntheticDecision(
                fromMode: currentMode,
                toMode: mode,
                accepted: false,
                status: .modeTransitionRejected,
                errorCode: .transitionDenied,
                message: "\(modeDisplayName(for: mode))当前未运行。"
            )
            return
        }

        let capturedTeachingSessionId = mode == .teaching ? activeObservationSessionId : nil
        cancelIntegratedWorkflowTask()
        stopObservationCapture()
        runningMode = nil
        selectedMode = mode
        applySyntheticDecision(
            fromMode: mode,
            toMode: mode,
            accepted: true,
            status: .modeStable,
            message: "\(modeDisplayName(for: mode))已停止。"
        )
        refreshLearningStatusSurface(forceTeacherPaused: false)

        if let capturedTeachingSessionId {
            runTeachingPostProcessing(for: capturedTeachingSessionId)
        }
    }

    func toggleMode(_ mode: OpenStaffMode) {
        if isModeRunning(mode) {
            stopMode(mode)
        } else {
            startMode(mode)
        }
    }

    func refreshDashboard(promptAccessibilityPermission: Bool) {
        permissionSnapshot = permissionSnapshotProvider(promptAccessibilityPermission)
        recentTasks = RecentTaskRepository.loadRecentTasks(limit: 20)
        learningSnapshot = LearningRecordRepository.loadLearningSnapshot()
        learningSessions = learningSnapshot.sessions
        reconcileLearningSelection()
        refreshExecutionReview()
        refreshLearnedSkills()
        refreshExecutorHelperPath()
        lastRefreshedAt = Date()
        refreshLearningStatusSurface(updatePermissionSnapshot: false)
    }

    func selectLearningSession(_ sessionId: String?) {
        selectedLearningSessionId = sessionId
        reconcileTaskSelectionForCurrentSession()
    }

    func selectLearningTask(_ taskId: String?) {
        selectedLearningTaskId = taskId
    }

    func selectExecutionLog(_ logId: String?) {
        selectedExecutionLogId = logId
        quickFeedbackStatusMessage = nil
        refreshSelectedLogFeedback()
        refreshSelectedExecutionReviewDetail()
    }

    func selectLearnedSkill(_ skillId: String?) {
        selectedLearnedSkillId = skillId
        selectedSkillDriftReport = nil
        selectedSkillRepairPlan = nil
        refreshSelectedSkillReview()
    }

    func runLearnedSkill(_ skillId: String) {
        guard runningMode == .student else {
            skillActionSucceeded = false
            skillActionStatusMessage = "请先启动学生模式，再运行技能。"
            return
        }
        guard let skill = learnedSkillSnapshot.skillsById[skillId] else {
            skillActionSucceeded = false
            skillActionStatusMessage = "未找到技能，无法运行。"
            return
        }
        if skill.preflight.status == .failed {
            skillActionSucceeded = false
            skillActionStatusMessage = "技能预检失败，已禁止运行：\(skill.preflight.summary)\n\(skill.preflightIssueSummary)"
            return
        }
        guard skill.llmOutputAccepted else {
            skillActionSucceeded = false
            skillActionStatusMessage = "技能未通过 LLM 结构校验（当前为 fallback 结果），已禁止运行。请修正手动粘贴结果并重新生成技能。"
            return
        }
        if let review = skill.review, review.decision == .rejected {
            skillActionSucceeded = false
            skillActionStatusMessage = "技能已被驳回，禁止运行。请修正后重新审核。"
            return
        }
        if skill.requiresApprovedTeacherConfirmation,
           skill.review?.decision != .approved {
            skillActionSucceeded = false
            skillActionStatusMessage = "技能命中预检安全门，需要老师先执行“审核 -> 通过”后才能手动运行。\n\(skill.preflightIssueSummary)"
            return
        }
        guard !skillActionProcessing else {
            return
        }

        skillActionProcessing = true
        skillActionSucceeded = true
        skillActionStatusMessage = "正在运行技能：\(skill.skillName)..."
        let emergencyStopActive = self.emergencyStopActive

        Task.detached(priority: .userInitiated) {
            do {
                let result = try LearnedSkillRunner.run(
                    skill: skill,
                    emergencyStopActive: emergencyStopActive,
                    automaticExecution: false,
                    teacherConfirmationGranted: skill.review?.decision == .approved
                )
                await MainActor.run { [weak self] in
                    let hasQualityWarnings = !result.qualityWarnings.isEmpty
                    let warningText = result.qualityWarnings.joined(separator: "；")
                    self?.skillActionProcessing = false
                    self?.skillActionSucceeded = !hasQualityWarnings
                    if hasQualityWarnings {
                        self?.skillActionStatusMessage = "技能执行完成（部分）：总步骤 \(result.totalSteps)，成功 \(result.succeededSteps)，失败 \(result.failedSteps)，阻塞 \(result.blockedSteps)。质量提示：\(warningText)。日志：\(result.logFilePath)"
                    } else {
                        self?.skillActionStatusMessage = "技能运行完成：总步骤 \(result.totalSteps)，成功 \(result.succeededSteps)，失败 \(result.failedSteps)，阻塞 \(result.blockedSteps)。日志：\(result.logFilePath)"
                    }
                    self?.refreshDashboard(promptAccessibilityPermission: false)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.skillActionProcessing = false
                    self?.skillActionSucceeded = false
                    self?.skillActionStatusMessage = "运行技能失败：\(error.localizedDescription)"
                    self?.refreshExecutorHelperPath()
                }
            }
        }
    }

    func deleteLearnedSkill(_ skillId: String) {
        guard let skill = learnedSkillSnapshot.skillsById[skillId] else {
            skillActionSucceeded = false
            skillActionStatusMessage = "未找到技能，无法删除。"
            return
        }

        do {
            try LearnedSkillRepository.deleteSkillDirectory(at: skill.skillDirectoryURL)
            skillActionSucceeded = true
            skillActionStatusMessage = "已删除技能：\(skill.skillName)"
            refreshLearnedSkills()
        } catch {
            skillActionSucceeded = false
            skillActionStatusMessage = "删除技能失败：\(error.localizedDescription)"
        }
    }

    func reviewLearnedSkill(_ skillId: String, decision: LearnedSkillReviewDecision) {
        guard let skill = learnedSkillSnapshot.skillsById[skillId] else {
            skillActionSucceeded = false
            skillActionStatusMessage = "未找到技能，无法审核。"
            return
        }

        let entry = LearnedSkillReviewWriteEntry(
            reviewId: "skill-review-\(UUID().uuidString.lowercased())",
            timestamp: OpenStaffDateFormatter.iso8601String(from: Date()),
            skillId: skill.id,
            skillName: skill.skillName,
            decision: decision,
            skillDirectoryPath: skill.skillDirectoryPath
        )

        do {
            try LearnedSkillReviewWriter.append(entry)
            skillActionSucceeded = true
            skillActionStatusMessage = "已审核技能：\(skill.skillName)（\(decision.displayName)）"
            refreshLearnedSkills()
        } catch {
            skillActionSucceeded = false
            skillActionStatusMessage = "审核技能失败：\(error.localizedDescription)"
        }
    }

    func detectSelectedSkillDrift() {
        guard let skill = selectedLearnedSkill else {
            skillActionSucceeded = false
            skillActionStatusMessage = "未选择技能，无法检测漂移。"
            return
        }
        guard !skillDriftProcessing else {
            return
        }

        skillDriftProcessing = true
        selectedSkillDriftReport = nil
        selectedSkillRepairPlan = nil
        skillActionSucceeded = true
        skillActionStatusMessage = "正在检测技能漂移：\(skill.skillName)..."

        Task.detached(priority: .userInitiated) {
            do {
                let payload = try SkillPreflightValidator().loadSkillBundle(from: skill.skillDirectoryURL)
                let snapshot = LiveReplayEnvironmentSnapshotProvider().snapshot()
                let driftReport = SkillDriftDetector().detect(
                    payload: payload,
                    snapshot: snapshot,
                    skillDirectoryPath: skill.skillDirectoryPath
                )
                let preferenceSnapshot = try? PreferenceMemoryStore(
                    preferencesRootDirectory: OpenStaffWorkspacePaths.preferencesDirectory
                ).loadLatestProfileSnapshot()
                let repairPlanner = PreferenceAwareSkillRepairPlanner(
                    preferenceProfile: preferenceSnapshot?.profile
                )
                let repairPlan = repairPlanner.buildPlan(
                    report: driftReport,
                    payload: payload
                )
                if let policyAssemblyWriter = PolicyAssemblyDecisionFeatureFlag.storeIfEnabled(
                    preferencesRootDirectory: OpenStaffWorkspacePaths.preferencesDirectory
                ) {
                    try policyAssemblyWriter.store(
                        repairPlanner.buildPolicyAssemblyDecision(
                            report: driftReport,
                            payload: payload,
                            plan: repairPlan
                        )
                    )
                }

                await MainActor.run { [weak self] in
                    self?.skillDriftProcessing = false
                    self?.selectedSkillDriftReport = driftReport
                    self?.selectedSkillRepairPlan = repairPlan
                    self?.skillActionSucceeded = driftReport.status == .stable
                    if driftReport.status == .stable {
                        self?.skillActionStatusMessage = "技能漂移检测完成：未发现明显漂移。"
                    } else {
                        self?.skillActionStatusMessage = "技能漂移检测完成：\(repairPlan.summary)"
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.skillDriftProcessing = false
                    self?.skillActionSucceeded = false
                    self?.skillActionStatusMessage = "技能漂移检测失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func recordSelectedSkillRepairAction(_ actionId: String) {
        guard let skill = selectedLearnedSkill else {
            skillActionSucceeded = false
            skillActionStatusMessage = "未选择技能，无法记录修复动作。"
            return
        }
        guard let repairPlan = selectedSkillRepairPlan,
              let action = repairPlan.actions.first(where: { $0.actionId == actionId }) else {
            skillActionSucceeded = false
            skillActionStatusMessage = "当前没有可记录的修复动作。"
            return
        }

        let entry = SkillRepairRequestWriteEntry(
            requestId: "skill-repair-\(UUID().uuidString.lowercased())",
            timestamp: OpenStaffDateFormatter.iso8601String(from: Date()),
            skillId: skill.id,
            skillName: skill.skillName,
            skillDirectoryPath: skill.skillDirectoryPath,
            actionType: action.type.rawValue,
            actionTitle: action.title,
            actionReason: action.reason,
            affectedStepIds: action.affectedStepIds,
            dominantDriftKind: repairPlan.dominantDriftKind.rawValue,
            recommendedRepairVersion: repairPlan.recommendedRepairVersion
        )

        do {
            try SkillRepairRequestWriter.append(entry)
            skillActionSucceeded = true
            skillActionStatusMessage = "已记录修复动作：\(action.title)。建议 repairVersion 更新到 \(repairPlan.recommendedRepairVersion ?? ((repairPlan.currentRepairVersion ?? 0) + 1))。"
        } catch {
            skillActionSucceeded = false
            skillActionStatusMessage = "记录修复动作失败：\(error.localizedDescription)"
        }
    }

    func submitTeacherFeedback(decision: TeacherFeedbackDecision) {
        guard let selectedExecutionLog else {
            quickFeedbackWriteSucceeded = false
            quickFeedbackStatusMessage = "未选择执行日志，无法提交反馈。"
            return
        }

        let trimmedNote = quickFeedbackNoteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if decision == .needsRevision && trimmedNote.isEmpty {
            quickFeedbackWriteSucceeded = false
            quickFeedbackStatusMessage = "修正反馈需填写备注。"
            return
        }

        let repairAction: ExecutionReviewRepairAction?
        switch decision {
        case .fixLocator:
            repairAction = selectedExecutionReviewDetail?.locatorRepairAction
        case .reteach:
            repairAction = selectedExecutionReviewDetail?.reteachAction
        default:
            repairAction = nil
        }

        if (decision == .fixLocator || decision == .reteach), repairAction == nil {
            quickFeedbackWriteSucceeded = false
            quickFeedbackStatusMessage = "当前日志未关联到可修复的 skill，无法直接发起修复动作。"
            return
        }

        let entry = TeacherFeedbackWriteEntry(
            feedbackId: "feedback-\(UUID().uuidString.lowercased())",
            timestamp: OpenStaffDateFormatter.iso8601String(from: Date()),
            decision: decision,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            sessionId: selectedExecutionLog.sessionId,
            taskId: selectedExecutionLog.taskId,
            logEntryId: selectedExecutionLog.id,
            logStatus: selectedExecutionLog.status,
            logMessage: selectedExecutionLog.message,
            component: selectedExecutionLog.component,
            repairActionType: repairAction?.type.rawValue,
            repairStepIds: repairAction?.affectedStepIds,
            skillName: selectedExecutionReviewDetail?.skillName,
            skillDirectoryPath: selectedExecutionReviewDetail?.skillDirectoryPath
        )

        do {
            try executionReviewStore.appendTeacherFeedback(entry)
        } catch {
            quickFeedbackWriteSucceeded = false
            quickFeedbackStatusMessage = "反馈保存失败：\(error.localizedDescription)"
            return
        }

        if let repairAction {
            do {
                try appendRepairRequest(for: repairAction)
                quickFeedbackNoteInput = ""
                quickFeedbackWriteSucceeded = true
                quickFeedbackStatusMessage = "反馈已保存，并已发起修复动作：\(repairAction.title)"
                refreshExecutionReview()
            } catch {
                quickFeedbackNoteInput = ""
                quickFeedbackWriteSucceeded = false
                quickFeedbackStatusMessage = "反馈已保存，但修复动作写入失败：\(error.localizedDescription)"
                refreshExecutionReview()
            }
            return
        }

        quickFeedbackNoteInput = ""
        quickFeedbackWriteSucceeded = true
        quickFeedbackStatusMessage = "反馈已保存：\(decision.displayName)"
        refreshExecutionReview()
    }

    func startSafetyControlsIfNeeded() {
        guard !safetyControlsStarted else {
            return
        }
        safetyControlsStarted = true
        emergencyStopHotkeyMonitor.start()
        startLearningStatusRefreshTimerIfNeeded()
        refreshLearningStatusSurface()
    }

    func activateEmergencyStop(source: EmergencyStopSource) {
        if let runningMode {
            self.runningMode = nil
            transitionMessage = "安全控制：紧急停止已激活，\(modeDisplayName(for: runningMode))已停止。"
        }
        cancelIntegratedWorkflowTask()
        stopObservationCapture()
        teachingSkillProcessing = false
        emergencyStopActive = true
        emergencyStopActivatedAt = Date()
        emergencyStopSource = source
        guardInputs.emergencyStopActive = true

        refreshLearningStatusSurface(forceTeacherPaused: false)
    }

    func releaseEmergencyStop() {
        emergencyStopActive = false
        emergencyStopActivatedAt = nil
        emergencyStopSource = nil
        guardInputs.emergencyStopActive = false

        refreshLearningStatusSurface(forceTeacherPaused: false)
    }

    func quickFeedbackDisabledReason(for action: TeacherQuickFeedbackAction) -> String? {
        guard selectedExecutionLog != nil else {
            return "未选择执行日志。"
        }

        switch action {
        case .fixLocator:
            if selectedExecutionReviewDetail?.locatorRepairAction == nil {
                return "当前日志没有可修 locator 的结构化修复入口。"
            }
        case .reteach:
            if selectedExecutionReviewDetail?.reteachAction == nil {
                return "当前日志没有可重示教的结构化修复入口。"
            }
        case .approved, .rejected, .needsRevision, .tooDangerous, .wrongOrder, .wrongStyle:
            break
        }

        return nil
    }

    private func handleCapturedEventCountUpdate(_ count: Int) {
        if ignoreNextObservationResetCount && count == 0 {
            ignoreNextObservationResetCount = false
            return
        }

        capturedEventCount = capturedEventBaseCount + count
        if count > 0 {
            lastSuccessfulLearningWriteAt = nowProvider()
        }

        refreshLearningStatusSurface(
            updatePermissionSnapshot: false,
            refreshContext: false,
            syncObservationCapture: false
        )
    }

    private func startLearningStatusRefreshTimerIfNeeded() {
        guard learningStatusRefreshTimer == nil else {
            return
        }

        let timerTarget = DashboardLearningStatusRefreshTimerTarget(owner: self)
        learningStatusRefreshTimerTarget = timerTarget
        learningStatusRefreshTimer = Timer.scheduledTimer(
            timeInterval: 1.5,
            target: timerTarget,
            selector: #selector(DashboardLearningStatusRefreshTimerTarget.handleTick(_:)),
            userInfo: nil,
            repeats: true
        )
        if let learningStatusRefreshTimer {
            RunLoop.main.add(learningStatusRefreshTimer, forMode: .common)
        }
    }

    func refreshLearningStatusSurface(
        forceTeacherPaused: Bool? = nil,
        updatePermissionSnapshot: Bool = true,
        refreshContext: Bool = true,
        syncObservationCapture: Bool = true
    ) {
        if updatePermissionSnapshot {
            permissionSnapshot = permissionSnapshotProvider(false)
        }

        if refreshContext {
            latestLearningContextSnapshot = learningContextSnapshotProvider.snapshot(
                includeWindowContext: permissionSnapshot.accessibilityTrusted
            )
        }

        if lastSuccessfulLearningWriteAt == nil {
            lastSuccessfulLearningWriteAt = learningLastSuccessfulWriteProvider.latestSuccessfulWriteAt(
                rawEventsRootDirectory: OpenStaffWorkspacePaths.rawEventsDirectory
            )
        }

        let normalizedLearningPrivacyConfiguration = normalizeLearningPrivacyConfigurationIfNeeded()
        let teacherPaused = forceTeacherPaused ?? learningSessionState.teacherPaused
        let observesTeacherActions = runningMode.map(shouldObserveTeacherActions(for:)) ?? false
        let currentApp = LearningSurfaceAppContext(snapshot: latestLearningContextSnapshot)
        let exclusionPolicy = LearningAppExclusionPolicy.default(
            settings: normalizedLearningPrivacyConfiguration
        )
        let exclusionMatch = exclusionPolicy.match(for: currentApp)
        let sensitiveMatch = learningSensitiveScenePolicy.match(
            for: currentApp,
            enabledRuleIds: normalizedLearningPrivacyConfiguration.effectiveEnabledSensitiveSceneRuleIds
        )
        let temporaryPauseUntil = normalizedLearningPrivacyConfiguration.temporaryPauseUntil
        let shouldRunCapture = runningMode != nil
            && observesTeacherActions
            && !teacherPaused
            && temporaryPauseUntil == nil
            && !emergencyStopActive
            && exclusionMatch == nil
            && sensitiveMatch == nil

        if syncObservationCapture {
            do {
                if shouldRunCapture, let runningMode {
                    try ensureObservationCaptureRunning(
                        for: runningMode,
                        permissionSnapshot: permissionSnapshot,
                        announceStatus: false
                    )
                } else if modeObservationCapture.isRunning {
                    stopObservationCapture(
                        clearSessionContext: runningMode == nil || !observesTeacherActions,
                        resetCapturedEventCount: runningMode == nil || !observesTeacherActions
                    )
                }
            } catch {
                handleObservationCaptureFailure(error)
                return
            }
        }

        learningSessionState = LearningSessionStateResolver.resolve(
            LearningSessionStateInput(
                selectedMode: selectedMode,
                runningMode: runningMode,
                observesTeacherActions: observesTeacherActions,
                captureRunning: modeObservationCapture.isRunning,
                teacherPaused: teacherPaused,
                temporaryPauseUntil: temporaryPauseUntil,
                currentApp: currentApp,
                exclusionMatch: exclusionMatch,
                sensitiveMatch: sensitiveMatch,
                lastSuccessfulWriteAt: lastSuccessfulLearningWriteAt,
                activeSessionId: activeObservationSessionId,
                capturedEventCount: capturedEventCount,
                updatedAt: nowProvider()
            )
        )
    }

    private func normalizeLearningPrivacyConfigurationIfNeeded() -> LearningPrivacyConfiguration {
        let normalized = learningPrivacyConfiguration.normalized(referenceDate: nowProvider())
        guard normalized != learningPrivacyConfiguration else {
            return learningPrivacyConfiguration
        }

        do {
            try learningPrivacyConfigurationStore.save(normalized)
        } catch {
            learningPrivacyConfiguration = normalized
            return normalized
        }

        learningPrivacyConfiguration = normalized
        return normalized
    }

    private func updateLearningPrivacyConfiguration(
        successMessage: String?,
        announceResult: Bool = true,
        mutate: (inout LearningPrivacyConfiguration) -> Void
    ) {
        var updatedConfiguration = learningPrivacyConfiguration
        mutate(&updatedConfiguration)
        updatedConfiguration = updatedConfiguration.normalized(referenceDate: nowProvider())

        guard updatedConfiguration != learningPrivacyConfiguration else {
            if let successMessage, announceResult {
                learningPrivacyStatusSucceeded = true
                learningPrivacyStatusMessage = successMessage
            }
            refreshLearningStatusSurface(refreshContext: false)
            return
        }

        do {
            try learningPrivacyConfigurationStore.save(updatedConfiguration)
            learningPrivacyConfiguration = updatedConfiguration
            if announceResult {
                learningPrivacyStatusSucceeded = true
                learningPrivacyStatusMessage = successMessage
            }
            refreshLearningStatusSurface(refreshContext: false)
        } catch {
            if announceResult {
                learningPrivacyStatusSucceeded = false
                learningPrivacyStatusMessage = "保存隐私规则失败：\(error.localizedDescription)"
            }
        }
    }

    private func startObservationCaptureIfNeeded(for mode: OpenStaffMode) throws {
        guard shouldObserveTeacherActions(for: mode) else {
            stopObservationCapture()
            transitionMessage = "\(modeDisplayName(for: mode))已开始运行。"
            return
        }

        let snapshot = permissionSnapshotProvider(false)
        permissionSnapshot = snapshot

        try ensureObservationCaptureRunning(
            for: mode,
            permissionSnapshot: snapshot,
            announceStatus: true
        )
    }

    private func ensureObservationCaptureRunning(
        for mode: OpenStaffMode,
        permissionSnapshot: PermissionSnapshot,
        announceStatus: Bool
    ) throws {
        guard permissionSnapshot.dataDirectoryWritable else {
            throw DashboardCaptureStartupError.dataDirectoryNotWritable(OpenStaffWorkspacePaths.dataDirectory.path)
        }

        if modeObservationCapture.isRunning {
            if announceStatus {
                transitionMessage = "\(modeDisplayName(for: mode))已开始运行，正在记录操作事件（sessionId=\(activeObservationSessionId ?? sessionId)）。"
            }
            return
        }

        let captureSessionId = activeObservationSessionId ?? makeObservationSessionId(for: mode)
        try modeObservationCapture.start(
            sessionId: captureSessionId,
            includeWindowContext: permissionSnapshot.accessibilityTrusted
        )
        activeObservationSessionId = captureSessionId
        if !announceStatus {
            return
        }

        if permissionSnapshot.accessibilityTrusted {
            transitionMessage = "\(modeDisplayName(for: mode))已开始运行，正在记录操作事件（sessionId=\(captureSessionId)）。"
        } else {
            let executablePath = ProcessInfo.processInfo.arguments.first ?? "unknown"
            let debugHint: String
            if executablePath.contains("/DerivedData/") {
                debugHint = "（检测到 Xcode 调试路径：请在系统设置中同时勾选 Xcode 与 OpenStaffApp，授权后重启 App 再刷新。）"
            } else {
                debugHint = ""
            }
            transitionMessage = "\(modeDisplayName(for: mode))已开始运行（降级采集）。当前未授予辅助功能权限，窗口标题/窗口 ID 不会记录。可在系统设置授权后点击“刷新任务与权限”。授权目标：\(executablePath)\(debugHint)"
        }
    }

    private func stopObservationCapture(
        clearSessionContext: Bool = true,
        resetCapturedEventCount: Bool = true
    ) {
        if clearSessionContext || resetCapturedEventCount {
            capturedEventBaseCount = 0
            ignoreNextObservationResetCount = false
        } else {
            capturedEventBaseCount = capturedEventCount
            ignoreNextObservationResetCount = true
        }

        if modeObservationCapture.isRunning {
            modeObservationCapture.stop()
        }
        if clearSessionContext {
            activeObservationSessionId = nil
        }
        if resetCapturedEventCount {
            capturedEventCount = 0
        }
    }

    private func shouldObserveTeacherActions(for mode: OpenStaffMode) -> Bool {
        stateMachine
            .allowedCapabilities(for: mode)
            .contains(.observeTeacherActions)
    }

    private func makeObservationSessionId(for mode: OpenStaffMode) -> String {
        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(sessionId)-\(mode.rawValue)-\(formatter.string(from: timestamp))"
    }

    private func handleObservationCaptureFailure(_ error: Error) {
        stopObservationCapture()
        cancelIntegratedWorkflowTask()
        if let runningMode, shouldObserveTeacherActions(for: runningMode) {
            self.runningMode = nil
        }
        applySyntheticDecision(
            fromMode: currentMode,
            toMode: currentMode,
            accepted: false,
            status: .modeTransitionRejected,
            errorCode: .guardConditionFailed,
            message: "屏幕操作监控已停止：\(error.localizedDescription)"
        )
        refreshLearningStatusSurface(forceTeacherPaused: false)
    }

    private func startIntegratedWorkflowIfNeeded(for mode: OpenStaffMode) {
        cancelIntegratedWorkflowTask()

        switch mode {
        case .teaching:
            return
        case .assist:
            runAssistPostStartWorkflow()
        case .student:
            runStudentPostStartWorkflow()
        }
    }

    private func runTeachingPostProcessing(for capturedSessionId: String) {
        transitionMessage = "教学模式已停止，正在整理学习结果（切片 + 知识条目）..."
        integratedWorkflowTask = Task.detached(priority: .userInitiated) {
            let runner = IntegratedModeWorkflowRunner()
            do {
                let result = try runner.buildKnowledgeFromCapturedSession(sessionId: capturedSessionId)
                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    self.transitionMessage = "教学模式整理完成：session=\(result.sessionId)，事件 \(result.rawEventCount) 条，任务切片 \(result.taskChunkCount) 条，知识条目 \(result.knowledgeItemCount) 条。"
                    self.refreshDashboard(promptAccessibilityPermission: false)
                    self.handleTeachingPostProcessingResult(result)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.transitionMessage = "教学模式整理失败：\(error.localizedDescription)"
                    self?.teachingSkillProcessing = false
                    self?.teachingSkillStatusSucceeded = false
                    self?.teachingSkillStatusMessage = "教学模式整理失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func handleTeachingPostProcessingResult(_ result: IntegratedTeachingWorkflowResult) {
        guard let target = resolveTeachingKnowledgeTarget(from: result.knowledgeItemFilePaths) else {
            teachingSkillProcessing = false
            teachingSkillStatusSucceeded = false
            teachingSkillStatusMessage = "教学模式已完成知识整理，但未找到可用于 LLM 转换的知识条目文件。"
            return
        }

        latestTeachingKnowledgeTarget = target
        manualPromptPreviewText = ""
        manualLLMResultInput = ""
        latestGeneratedSkillDirectoryPath = nil
        latestGeneratedSkillName = nil
        latestLLMOutputPath = nil
        teachingSkillStatusMessage = nil
        teachingSkillStatusSucceeded = true

        switch teachingSkillGenerationMethod {
        case .api:
            runOpenAIAdapterSkillGeneration(for: target)
        case .manual:
            runManualPromptRender(for: target)
        }
    }

    private func resolveTeachingKnowledgeTarget(from knowledgeItemFilePaths: [URL]) -> TeachingKnowledgeTarget? {
        let sortedPaths = knowledgeItemFilePaths.sorted { lhs, rhs in
            lhs.lastPathComponent < rhs.lastPathComponent
        }

        let decoder = JSONDecoder()
        for path in sortedPaths.reversed() {
            guard let data = try? Data(contentsOf: path),
                  let item = try? decoder.decode(KnowledgeItem.self, from: data) else {
                continue
            }
            return TeachingKnowledgeTarget(
                sessionId: item.sessionId,
                taskId: item.taskId,
                knowledgeItemId: item.knowledgeItemId,
                knowledgeItemPath: path
            )
        }
        return nil
    }

    private func runManualPromptRender(for target: TeachingKnowledgeTarget) {
        cancelIntegratedWorkflowTask()
        teachingSkillProcessing = true
        teachingSkillStatusSucceeded = true
        teachingSkillStatusMessage = "正在生成手动提示词..."
        transitionMessage = "教学后处理：正在渲染手动提示词。"

        integratedWorkflowTask = Task.detached(priority: .userInitiated) {
            let runner = IntegratedModeWorkflowRunner()
            do {
                let preview = try runner.renderManualPromptPreview(knowledgeItemPath: target.knowledgeItemPath)
                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    self.manualPromptPreviewText = preview
                    self.teachingSkillProcessing = false
                    self.teachingSkillStatusSucceeded = true
                    self.teachingSkillStatusMessage = "手动提示词已生成，可复制到 ChatGPT。"
                    self.transitionMessage = "教学后处理已就绪：请复制提示词并粘贴 ChatGPT，收到结果后回填执行。"
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.teachingSkillProcessing = false
                    self?.teachingSkillStatusSucceeded = false
                    self?.teachingSkillStatusMessage = "生成手动提示词失败：\(error.localizedDescription)"
                    self?.transitionMessage = "教学后处理失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func runOpenAIAdapterSkillGeneration(for target: TeachingKnowledgeTarget) {
        cancelIntegratedWorkflowTask()
        teachingSkillProcessing = true
        teachingSkillStatusSucceeded = true
        teachingSkillStatusMessage = "正在调用 ChatGPT API 并生成 OpenClaw Skill..."
        transitionMessage = "教学后处理：自动 API 转换进行中..."

        let model = resolvedOpenAIModelName()
        integratedWorkflowTask = Task.detached(priority: .userInitiated) {
            let runner = IntegratedModeWorkflowRunner()
            do {
                let result = try runner.buildSkillUsingOpenAIAdapter(
                    knowledgeItemPath: target.knowledgeItemPath,
                    model: model
                )
                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    self.latestGeneratedSkillDirectoryPath = result.skillDirectory.path
                    self.latestGeneratedSkillName = result.skillName
                    self.latestLLMOutputPath = result.llmOutputPath.path
                    self.teachingSkillProcessing = false
                    self.teachingSkillStatusSucceeded = true
                    self.refreshLearnedSkills()

                    let acceptedDescription = result.llmOutputAccepted
                        ? "LLM 输出已通过校验"
                        : "LLM 输出未完全通过校验，已按 fallback 生成"
                    let diagnosticDescription = result.diagnostics.isEmpty
                        ? ""
                        : "（诊断 \(result.diagnostics.count) 条）"
                    self.teachingSkillStatusMessage = "自动 API 转换完成：skill=\(result.skillName)，目录=\(result.skillDirectory.path)。\(acceptedDescription)\(diagnosticDescription)"
                    self.transitionMessage = "教学后处理完成：已生成 OpenClaw Skill（\(result.skillName)）。"
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.teachingSkillProcessing = false
                    self?.teachingSkillStatusSucceeded = false
                    self?.teachingSkillStatusMessage = "自动 API 转换失败：\(error.localizedDescription)"
                    self?.transitionMessage = "教学后处理失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func runManualSkillGeneration(
        for target: TeachingKnowledgeTarget,
        manualOutputText: String
    ) {
        cancelIntegratedWorkflowTask()
        teachingSkillProcessing = true
        teachingSkillStatusSucceeded = true
        teachingSkillStatusMessage = "正在执行手动结果并生成 OpenClaw Skill..."
        transitionMessage = "教学后处理：正在执行手动粘贴结果..."

        integratedWorkflowTask = Task.detached(priority: .userInitiated) {
            let runner = IntegratedModeWorkflowRunner()
            do {
                let result = try runner.buildSkillFromManualLLMOutput(
                    knowledgeItemPath: target.knowledgeItemPath,
                    llmOutputText: manualOutputText
                )
                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    self.latestGeneratedSkillDirectoryPath = result.skillDirectory.path
                    self.latestGeneratedSkillName = result.skillName
                    self.latestLLMOutputPath = result.llmOutputPath.path
                    self.manualLLMResultInput = ""
                    self.teachingSkillProcessing = false
                    self.teachingSkillStatusSucceeded = true
                    self.refreshLearnedSkills()

                    let acceptedDescription = result.llmOutputAccepted
                        ? "LLM 输出已通过校验"
                        : "LLM 输出未完全通过校验，已按 fallback 生成"
                    let firstDiagnostic = result.diagnostics.first?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let diagnosticDescription: String
                    if let firstDiagnostic, !firstDiagnostic.isEmpty {
                        diagnosticDescription = "（诊断 \(result.diagnostics.count) 条，首条：\(firstDiagnostic)）"
                    } else {
                        diagnosticDescription = result.diagnostics.isEmpty ? "" : "（诊断 \(result.diagnostics.count) 条）"
                    }
                    self.teachingSkillStatusMessage = "手动结果执行完成：skill=\(result.skillName)，目录=\(result.skillDirectory.path)。\(acceptedDescription)\(diagnosticDescription)"
                    self.transitionMessage = "教学后处理完成：手动粘贴结果已转换为 OpenClaw Skill。"
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.teachingSkillProcessing = false
                    self?.teachingSkillStatusSucceeded = false
                    self?.teachingSkillStatusMessage = "执行手动结果失败：\(error.localizedDescription)"
                    self?.transitionMessage = "教学后处理失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func resolvedOpenAIModelName() -> String {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["OPENSTAFF_OPENAI_MODEL"] {
            let normalized = override.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                return normalized
            }
        }
        return "gpt-4.1-mini"
    }

    private func runAssistPostStartWorkflow() {
        let workflowSessionId = activeObservationSessionId ?? sessionId
        let emergencyStopActive = self.emergencyStopActive

        transitionMessage = "辅助模式已启动，正在执行集成辅助流程..."
        integratedWorkflowTask = Task.detached(priority: .userInitiated) {
            let runner = IntegratedModeWorkflowRunner()
            do {
                let result = try runner.runAssistLoop(
                    sessionId: workflowSessionId,
                    emergencyStopActive: emergencyStopActive
                )

                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    self.transitionMessage = "辅助模式流程完成：\(result.message)"
                    self.refreshDashboard(promptAccessibilityPermission: false)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.transitionMessage = "辅助模式流程失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func runStudentPostStartWorkflow() {
        let workflowSessionId = activeObservationSessionId ?? sessionId
        let emergencyStopActive = self.emergencyStopActive

        refreshLearnedSkills()
        guard let selectedSkill = selectAutoRunnableSkill(preferredSessionId: workflowSessionId) else {
            transitionMessage = "学生模式已启动：未找到可自动执行的技能。要求：LLM 输出通过校验、预检通过且未被驳回；命中安全门或低置信技能不会直接自动执行。"
            return
        }

        transitionMessage = "学生模式已启动，正在自动执行技能：\(selectedSkill.skillName)..."
        skillActionProcessing = true
        skillActionSucceeded = true
        skillActionStatusMessage = "学生模式自动执行：\(selectedSkill.skillName)..."

        integratedWorkflowTask = Task.detached(priority: .userInitiated) {
            do {
                let result = try LearnedSkillRunner.run(
                    skill: selectedSkill,
                    emergencyStopActive: emergencyStopActive,
                    automaticExecution: true,
                    teacherConfirmationGranted: false
                )

                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    let hasQualityWarnings = !result.qualityWarnings.isEmpty
                    let warningText = result.qualityWarnings.joined(separator: "；")
                    self.skillActionProcessing = false
                    self.skillActionSucceeded = !hasQualityWarnings
                    if hasQualityWarnings {
                        self.skillActionStatusMessage = "学生模式自动执行完成（部分）：总步骤 \(result.totalSteps)，成功 \(result.succeededSteps)，失败 \(result.failedSteps)，阻塞 \(result.blockedSteps)。质量提示：\(warningText)。日志：\(result.logFilePath)"
                    } else {
                        self.skillActionStatusMessage = "学生模式自动执行完成：总步骤 \(result.totalSteps)，成功 \(result.succeededSteps)，失败 \(result.failedSteps)，阻塞 \(result.blockedSteps)。日志：\(result.logFilePath)"
                    }
                    self.transitionMessage = "学生模式流程完成：已执行技能 \(selectedSkill.skillName)。"
                    self.refreshDashboard(promptAccessibilityPermission: false)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.skillActionProcessing = false
                    self?.skillActionSucceeded = false
                    self?.skillActionStatusMessage = "学生模式自动执行失败：\(error.localizedDescription)"
                    self?.transitionMessage = "学生模式流程失败：\(error.localizedDescription)"
                    self?.refreshExecutorHelperPath()
                }
            }
        }
    }

    private func selectAutoRunnableSkill(preferredSessionId: String) -> LearnedSkillSummary? {
        let candidates = learnedSkillSnapshot.skills.filter { skill in
            guard skill.llmOutputAccepted else {
                return false
            }
            guard skill.isAutoRunnable else {
                return false
            }
            if let review = skill.review, review.decision == .rejected {
                return false
            }
            return true
        }
        guard !candidates.isEmpty else {
            return nil
        }

        let preferredSkillId = selectedLearnedSkillId
        let prefixMatch = "\(preferredSessionId)-"
        let sorted = candidates.sorted { lhs, rhs in
            let lhsScore = autoRunScore(
                skill: lhs,
                preferredSkillId: preferredSkillId,
                preferredSessionId: preferredSessionId,
                prefixMatch: prefixMatch
            )
            let rhsScore = autoRunScore(
                skill: rhs,
                preferredSkillId: preferredSkillId,
                preferredSessionId: preferredSessionId,
                prefixMatch: prefixMatch
            )
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            let lhsDate = lhs.createdAt ?? Date.distantPast
            let rhsDate = rhs.createdAt ?? Date.distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.skillName < rhs.skillName
        }

        return sorted.first
    }

    private func autoRunScore(
        skill: LearnedSkillSummary,
        preferredSkillId: String?,
        preferredSessionId: String,
        prefixMatch: String
    ) -> Int {
        var score = 0

        if preferredSkillId == skill.id {
            score += 1_000
        }
        if skill.sessionId == preferredSessionId {
            score += 300
        } else if skill.sessionId.hasPrefix(prefixMatch) {
            score += 220
        }

        if let review = skill.review, review.decision == .approved {
            score += 120
        }
        if skill.storageScope == .done {
            score += 40
        }

        return score
    }

    private func cancelIntegratedWorkflowTask() {
        integratedWorkflowTask?.cancel()
        integratedWorkflowTask = nil
    }

    private func applySyntheticDecision(
        fromMode: OpenStaffMode,
        toMode: OpenStaffMode,
        accepted: Bool,
        status: OrchestratorStatusCode,
        errorCode: OrchestratorErrorCode? = nil,
        message: String
    ) {
        let decision = ModeTransitionDecision(
            fromMode: fromMode,
            toMode: toMode,
            accepted: accepted,
            status: status,
            errorCode: errorCode,
            message: message
        )
        lastDecision = decision
        transitionMessage = decision.message
    }

    private func reconcileLearningSelection() {
        let sessionIds = Set(learningSessions.map(\.sessionId))
        if let selectedLearningSessionId, !sessionIds.contains(selectedLearningSessionId) {
            self.selectedLearningSessionId = nil
        }
        if self.selectedLearningSessionId == nil {
            self.selectedLearningSessionId = learningSessions.first?.sessionId
        }
        reconcileTaskSelectionForCurrentSession()
    }

    private func reconcileTaskSelectionForCurrentSession() {
        let tasks = tasksForSelectedSession
        let taskIds = Set(tasks.map(\.id))
        if let selectedLearningTaskId, !taskIds.contains(selectedLearningTaskId) {
            self.selectedLearningTaskId = nil
        }
        if self.selectedLearningTaskId == nil {
            self.selectedLearningTaskId = tasks.first?.id
        }
    }

    private func refreshExecutionReview() {
        executionReviewSnapshot = executionReviewStore.loadExecutionSnapshot(limit: 120)
        executionLogs = executionReviewSnapshot.logs
        reconcileExecutionSelection()
        refreshSelectedLogFeedback()
        refreshSelectedExecutionReviewDetail()
    }

    private func reconcileExecutionSelection() {
        let logIds = Set(executionLogs.map(\.id))
        if let selectedExecutionLogId, !logIds.contains(selectedExecutionLogId) {
            self.selectedExecutionLogId = nil
        }
        if self.selectedExecutionLogId == nil {
            self.selectedExecutionLogId = executionLogs.first?.id
        }
    }

    private func refreshSelectedLogFeedback() {
        guard let selectedExecutionLogId else {
            latestFeedbackForSelectedLog = nil
            return
        }
        latestFeedbackForSelectedLog = executionReviewSnapshot.latestFeedbackByLogId[selectedExecutionLogId]
    }

    private func refreshSelectedExecutionReviewDetail() {
        guard let log = selectedExecutionLog else {
            selectedExecutionReviewDetail = nil
            return
        }
        selectedExecutionReviewDetail = executionReviewStore.loadDetail(for: log)
    }

    private func appendRepairRequest(for action: ExecutionReviewRepairAction) throws {
        guard let detail = selectedExecutionReviewDetail,
              let skillId = detail.skillId,
              let skillName = detail.skillName,
              let skillDirectoryPath = detail.skillDirectoryPath else {
            return
        }

        let repairVersion = detail.currentRepairVersion ?? 0
        let entry = SkillRepairRequestWriteEntry(
            requestId: "skill-repair-\(UUID().uuidString.lowercased())",
            timestamp: OpenStaffDateFormatter.iso8601String(from: Date()),
            skillId: skillId,
            skillName: skillName,
            skillDirectoryPath: skillDirectoryPath,
            actionType: action.type.rawValue,
            actionTitle: action.title,
            actionReason: action.reason,
            affectedStepIds: action.affectedStepIds,
            dominantDriftKind: "execution_review_feedback",
            recommendedRepairVersion: repairVersion + 1
        )

        try SkillRepairRequestWriter.append(entry)
    }

    private func refreshLearnedSkills() {
        learnedSkillSnapshot = LearnedSkillRepository.loadSnapshot()
        learnedSkills = learnedSkillSnapshot.skills
        reconcileLearnedSkillSelection()
        refreshSelectedSkillReview()
    }

    private func reconcileLearnedSkillSelection() {
        let skillIds = Set(learnedSkills.map(\.id))
        if let selectedLearnedSkillId, !skillIds.contains(selectedLearnedSkillId) {
            self.selectedLearnedSkillId = nil
        }
        if self.selectedLearnedSkillId == nil {
            self.selectedLearnedSkillId = learnedSkills.first?.id
        }
    }

    private func refreshSelectedSkillReview() {
        guard let selectedLearnedSkillId else {
            selectedLearnedSkillReview = nil
            return
        }
        selectedLearnedSkillReview = learnedSkillSnapshot.latestReviewBySkillId[selectedLearnedSkillId]
    }

    private func refreshExecutorHelperPath() {
        let backend = OpenStaffActionExecutor.backend
        executorBackendDescription = backend.displayName
        usesHelperExecutorBackend = backend == .helper
        if usesHelperExecutorBackend {
            executorHelperPath = OpenStaffExecutorXPCClient.shared.currentHelperExecutablePath()
        } else {
            executorHelperPath = nil
        }
    }
}

struct ModeGuardInput {
    var teacherConfirmed = true
    var learnedKnowledgeReady = true
    var executionPlanReady = true
    var pendingAssistSuggestion = false
    var emergencyStopActive = false
}

struct PermissionSnapshot {
    let accessibilityTrusted: Bool
    let dataDirectoryWritable: Bool

    static let unknown = PermissionSnapshot(accessibilityTrusted: false, dataDirectoryWritable: false)

    static func capture(promptAccessibilityPermission: Bool) -> PermissionSnapshot {
        let checker = AccessibilityPermissionChecker()
        let trusted = checker.isTrusted(prompt: promptAccessibilityPermission)
        let writable = OpenStaffWorkspacePaths.ensureDataDirectoryWritable()
        return PermissionSnapshot(accessibilityTrusted: trusted, dataDirectoryWritable: writable)
    }
}

struct AccessibilityPermissionChecker {
    func isTrusted(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        guard prompt else {
            return false
        }

        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

struct RecentTaskSummary: Identifiable {
    let mode: OpenStaffMode
    let sessionId: String
    let taskId: String
    let status: String
    let message: String
    let timestamp: Date

    var id: String {
        "\(mode.rawValue)|\(sessionId)|\(taskId)|\(status)"
    }
}

enum RecentTaskRepository {
    private static let decoder = JSONDecoder()

    static func loadRecentTasks(limit: Int) -> [RecentTaskSummary] {
        let logTasks = loadRecentTasksFromLogs()
        let knowledgeTasks = loadRecentTasksFromKnowledge()
        let merged = mergeLatestByTask(logTasks + knowledgeTasks)
        return Array(merged.prefix(limit))
    }

    private static func loadRecentTasksFromLogs() -> [RecentTaskSummary] {
        let logsRoot = OpenStaffWorkspacePaths.logsDirectory
        let logFiles = listFiles(withExtension: "log", under: logsRoot)
        guard !logFiles.isEmpty else {
            return []
        }

        var tasks: [RecentTaskSummary] = []
        tasks.reserveCapacity(64)

        for fileURL in logFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            for line in content.split(whereSeparator: \.isNewline) {
                guard let data = line.data(using: .utf8),
                      let logEntry = try? decoder.decode(RecentTaskLogEntry.self, from: data),
                      let taskId = logEntry.taskId,
                      let timestamp = OpenStaffDateFormatter.date(from: logEntry.timestamp) else {
                    continue
                }

                let mode = inferMode(component: logEntry.component)
                let summary = RecentTaskSummary(
                    mode: mode,
                    sessionId: logEntry.sessionId,
                    taskId: taskId,
                    status: logEntry.status,
                    message: logEntry.message,
                    timestamp: timestamp
                )
                tasks.append(summary)
            }
        }

        return tasks
    }

    private static func loadRecentTasksFromKnowledge() -> [RecentTaskSummary] {
        let knowledgeRoot = OpenStaffWorkspacePaths.knowledgeDirectory
        let knowledgeFiles = listFiles(withExtension: "json", under: knowledgeRoot)
        guard !knowledgeFiles.isEmpty else {
            return []
        }

        var tasks: [RecentTaskSummary] = []
        tasks.reserveCapacity(16)

        for fileURL in knowledgeFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  let item = try? decoder.decode(RecentKnowledgeItem.self, from: data),
                  let timestamp = OpenStaffDateFormatter.date(from: item.createdAt) else {
                continue
            }

            let summary = RecentTaskSummary(
                mode: .teaching,
                sessionId: item.sessionId,
                taskId: item.taskId,
                status: "STATUS_KNO_KNOWLEDGE_READY",
                message: item.summary,
                timestamp: timestamp
            )
            tasks.append(summary)
        }

        return tasks
    }

    private static func mergeLatestByTask(_ tasks: [RecentTaskSummary]) -> [RecentTaskSummary] {
        var latestByKey: [String: RecentTaskSummary] = [:]
        latestByKey.reserveCapacity(tasks.count)

        for task in tasks {
            let key = "\(task.mode.rawValue)|\(task.sessionId)|\(task.taskId)"
            guard let existing = latestByKey[key] else {
                latestByKey[key] = task
                continue
            }
            if task.timestamp > existing.timestamp {
                latestByKey[key] = task
            }
        }

        return latestByKey
            .values
            .sorted { lhs, rhs in
                lhs.timestamp > rhs.timestamp
            }
    }

    private static func inferMode(component: String?) -> OpenStaffMode {
        let componentValue = component ?? ""
        if componentValue.contains("student") {
            return .student
        }
        if componentValue.contains("assist") {
            return .assist
        }
        return .teaching
    }

    private static func listFiles(withExtension pathExtension: String, under root: URL) -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == pathExtension {
            urls.append(fileURL)
        }
        return urls
    }
}

private struct RecentTaskLogEntry: Decodable {
    let timestamp: String
    let sessionId: String
    let taskId: String?
    let status: String
    let message: String
    let component: String?
}

private struct RecentKnowledgeItem: Decodable {
    let taskId: String
    let sessionId: String
    let summary: String
    let createdAt: String
}

struct LearningSessionSummary: Identifiable {
    let sessionId: String
    let startedAt: Date?
    let endedAt: Date?
    let taskCount: Int
    let knowledgeItemCount: Int

    var id: String {
        sessionId
    }
}

struct LearningTaskSummary: Identifiable {
    let taskId: String
    let sessionId: String
    let startedAt: Date?
    let endedAt: Date?
    let eventCount: Int?
    let boundaryReason: String?
    let appName: String?
    let knowledgeStepCount: Int?

    var id: String {
        "\(sessionId)|\(taskId)"
    }
}

struct LearningTaskDetail {
    let task: LearningTaskSummary
    let knowledgeItem: LearningKnowledgeItemDetail?
}

struct LearningKnowledgeItemDetail {
    let knowledgeItemId: String
    let goal: String
    let summary: String
    let contextAppName: String
    let contextBundleId: String
    let windowTitle: String?
    let createdAt: Date?
    let constraints: [LearningKnowledgeConstraint]
    let steps: [LearningKnowledgeStep]
}

struct LearningKnowledgeConstraint: Identifiable {
    let type: String
    let description: String

    var id: String {
        "\(type)|\(description)"
    }
}

struct LearningKnowledgeStep: Identifiable {
    let stepId: String
    let instruction: String
    let sourceEventIds: [String]

    var id: String {
        stepId
    }
}

struct LearningSnapshot {
    let sessions: [LearningSessionSummary]
    let tasksBySession: [String: [LearningTaskSummary]]
    let taskDetailsById: [String: LearningTaskDetail]

    static let empty = LearningSnapshot(sessions: [], tasksBySession: [:], taskDetailsById: [:])
}

enum LearningRecordRepository {
    private static let decoder = JSONDecoder()

    static func loadLearningSnapshot() -> LearningSnapshot {
        let chunkRecords = loadTaskChunkRecords()
        let knowledgeRecords = loadKnowledgeRecords()
        let knowledgeByTask = buildKnowledgeByTask(records: knowledgeRecords)

        var tasksBySession: [String: [LearningTaskSummary]] = [:]
        var taskDetailsById: [String: LearningTaskDetail] = [:]
        var sessionAggregates: [String: LearningSessionAggregate] = [:]

        for chunk in chunkRecords {
            let knowledge = knowledgeByTask[chunk.taskId]
            let task = LearningTaskSummary(
                taskId: chunk.taskId,
                sessionId: chunk.sessionId,
                startedAt: OpenStaffDateFormatter.date(from: chunk.startTimestamp),
                endedAt: OpenStaffDateFormatter.date(from: chunk.endTimestamp),
                eventCount: chunk.eventCount,
                boundaryReason: chunk.boundaryReason,
                appName: chunk.primaryContext.appName,
                knowledgeStepCount: knowledge?.steps.count
            )
            tasksBySession[chunk.sessionId, default: []].append(task)
            taskDetailsById[task.id] = LearningTaskDetail(task: task, knowledgeItem: mapKnowledgeDetail(knowledge))

            var aggregate = sessionAggregates[chunk.sessionId] ?? LearningSessionAggregate(sessionId: chunk.sessionId)
            aggregate.include(task: task, hasKnowledgeItem: knowledge != nil)
            sessionAggregates[chunk.sessionId] = aggregate
        }

        for knowledge in knowledgeRecords where taskDetailsById["\(knowledge.sessionId)|\(knowledge.taskId)"] == nil {
            let task = LearningTaskSummary(
                taskId: knowledge.taskId,
                sessionId: knowledge.sessionId,
                startedAt: nil,
                endedAt: OpenStaffDateFormatter.date(from: knowledge.createdAt),
                eventCount: nil,
                boundaryReason: nil,
                appName: knowledge.context.appName,
                knowledgeStepCount: knowledge.steps.count
            )
            tasksBySession[knowledge.sessionId, default: []].append(task)
            taskDetailsById[task.id] = LearningTaskDetail(task: task, knowledgeItem: mapKnowledgeDetail(knowledge))

            var aggregate = sessionAggregates[knowledge.sessionId] ?? LearningSessionAggregate(sessionId: knowledge.sessionId)
            aggregate.include(task: task, hasKnowledgeItem: true)
            sessionAggregates[knowledge.sessionId] = aggregate
        }

        let sortedTasksBySession = tasksBySession.mapValues { tasks in
            tasks.sorted { lhs, rhs in
                let lhsDate = lhs.endedAt ?? lhs.startedAt ?? Date.distantPast
                let rhsDate = rhs.endedAt ?? rhs.startedAt ?? Date.distantPast
                if lhsDate == rhsDate {
                    return lhs.taskId < rhs.taskId
                }
                return lhsDate > rhsDate
            }
        }

        let sessions = sessionAggregates
            .values
            .map { aggregate in
                LearningSessionSummary(
                    sessionId: aggregate.sessionId,
                    startedAt: aggregate.startedAt,
                    endedAt: aggregate.endedAt,
                    taskCount: aggregate.taskIds.count,
                    knowledgeItemCount: aggregate.knowledgeTaskIds.count
                )
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.endedAt ?? lhs.startedAt ?? Date.distantPast
                let rhsDate = rhs.endedAt ?? rhs.startedAt ?? Date.distantPast
                if lhsDate == rhsDate {
                    return lhs.sessionId < rhs.sessionId
                }
                return lhsDate > rhsDate
            }

        return LearningSnapshot(
            sessions: sessions,
            tasksBySession: sortedTasksBySession,
            taskDetailsById: taskDetailsById
        )
    }

    private static func loadTaskChunkRecords() -> [TaskChunkRecord] {
        let chunkFiles = listFiles(withExtension: "json", under: OpenStaffWorkspacePaths.taskChunksDirectory)
        guard !chunkFiles.isEmpty else {
            return []
        }

        var records: [TaskChunkRecord] = []
        records.reserveCapacity(chunkFiles.count)

        for fileURL in chunkFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  let record = try? decoder.decode(TaskChunkRecord.self, from: data) else {
                continue
            }
            records.append(record)
        }
        return records
    }

    private static func loadKnowledgeRecords() -> [KnowledgeItemRecord] {
        let files = listFiles(withExtension: "json", under: OpenStaffWorkspacePaths.knowledgeDirectory)
        guard !files.isEmpty else {
            return []
        }

        var records: [KnowledgeItemRecord] = []
        records.reserveCapacity(files.count)

        for fileURL in files {
            guard let data = try? Data(contentsOf: fileURL),
                  let record = try? decoder.decode(KnowledgeItemRecord.self, from: data) else {
                continue
            }
            records.append(record)
        }
        return records
    }

    private static func buildKnowledgeByTask(records: [KnowledgeItemRecord]) -> [String: KnowledgeItemRecord] {
        var byTask: [String: KnowledgeItemRecord] = [:]
        byTask.reserveCapacity(records.count)

        for item in records {
            guard let existing = byTask[item.taskId] else {
                byTask[item.taskId] = item
                continue
            }

            let existingDate = OpenStaffDateFormatter.date(from: existing.createdAt) ?? Date.distantPast
            let currentDate = OpenStaffDateFormatter.date(from: item.createdAt) ?? Date.distantPast
            if currentDate >= existingDate {
                byTask[item.taskId] = item
            }
        }

        return byTask
    }

    private static func mapKnowledgeDetail(_ item: KnowledgeItemRecord?) -> LearningKnowledgeItemDetail? {
        guard let item else {
            return nil
        }
        return LearningKnowledgeItemDetail(
            knowledgeItemId: item.knowledgeItemId,
            goal: item.goal,
            summary: item.summary,
            contextAppName: item.context.appName,
            contextBundleId: item.context.appBundleId,
            windowTitle: item.context.windowTitle,
            createdAt: OpenStaffDateFormatter.date(from: item.createdAt),
            constraints: item.constraints.map { constraint in
                LearningKnowledgeConstraint(type: constraint.type, description: constraint.description)
            },
            steps: item.steps.map { step in
                LearningKnowledgeStep(
                    stepId: step.stepId,
                    instruction: step.instruction,
                    sourceEventIds: step.sourceEventIds
                )
            }
        )
    }

    private static func listFiles(withExtension pathExtension: String, under root: URL) -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == pathExtension {
            urls.append(fileURL)
        }
        return urls
    }
}

private struct LearningSessionAggregate {
    let sessionId: String
    var startedAt: Date?
    var endedAt: Date?
    var taskIds: Set<String> = []
    var knowledgeTaskIds: Set<String> = []

    mutating func include(task: LearningTaskSummary, hasKnowledgeItem: Bool) {
        taskIds.insert(task.taskId)
        if hasKnowledgeItem {
            knowledgeTaskIds.insert(task.taskId)
        }

        if let taskStartedAt = task.startedAt {
            if let startedAt {
                self.startedAt = min(startedAt, taskStartedAt)
            } else {
                self.startedAt = taskStartedAt
            }
        }

        let taskEndedAt = task.endedAt ?? task.startedAt
        if let taskEndedAt {
            if let endedAt {
                self.endedAt = max(endedAt, taskEndedAt)
            } else {
                self.endedAt = taskEndedAt
            }
        }
    }
}

private struct TaskChunkRecord: Decodable {
    let taskId: String
    let sessionId: String
    let startTimestamp: String
    let endTimestamp: String
    let eventCount: Int
    let boundaryReason: String
    let primaryContext: TaskContextRecord
}

private struct TaskContextRecord: Decodable {
    let appName: String
}

private struct KnowledgeItemRecord: Decodable {
    let knowledgeItemId: String
    let taskId: String
    let sessionId: String
    let goal: String
    let summary: String
    let steps: [KnowledgeStepRecord]
    let context: KnowledgeContextRecord
    let constraints: [KnowledgeConstraintRecord]
    let createdAt: String
}

private struct KnowledgeStepRecord: Decodable {
    let stepId: String
    let instruction: String
    let sourceEventIds: [String]
}

private struct KnowledgeContextRecord: Decodable {
    let appName: String
    let appBundleId: String
    let windowTitle: String?
}

private struct KnowledgeConstraintRecord: Decodable {
    let type: String
    let description: String
}

enum LearnedSkillStorageScope: String {
    case pending
    case done

    var displayName: String {
        switch self {
        case .pending:
            return "pending"
        case .done:
            return "done"
        }
    }
}

enum LearnedSkillReviewDecision: String, Codable {
    case approved
    case rejected

    var displayName: String {
        switch self {
        case .approved:
            return "已通过"
        case .rejected:
            return "已驳回"
        }
    }
}

struct LearnedSkillReviewSummary {
    let decision: LearnedSkillReviewDecision
    let timestamp: Date
}

struct LearnedSkillSummary: Identifiable {
    let id: String
    let skillName: String
    let taskId: String
    let sessionId: String
    let knowledgeItemId: String
    let skillDirectoryPath: String
    let skillJSONPath: String
    let storageScope: LearnedSkillStorageScope
    let llmOutputAccepted: Bool
    let createdAt: Date?
    let review: LearnedSkillReviewSummary?
    let preflight: SkillPreflightReport

    var isReviewed: Bool {
        review != nil
    }

    var reviewStatusText: String {
        guard let review else {
            return "未审核"
        }
        return "\(review.decision.displayName) @ \(OpenStaffDateFormatter.displayString(from: review.timestamp))"
    }

    var storageScopeDisplayName: String {
        storageScope.displayName
    }

    var preflightStatusText: String {
        preflight.status.displayName
    }

    var preflightIssueSummary: String {
        preflight.userFacingIssueMessages.joined(separator: "\n")
    }

    var requiresApprovedTeacherConfirmation: Bool {
        preflight.requiresTeacherConfirmation
    }

    var isAutoRunnable: Bool {
        preflight.isAutoRunnable
    }

    var skillDirectoryURL: URL {
        URL(fileURLWithPath: skillDirectoryPath, isDirectory: true)
    }

    var skillJSONURL: URL {
        URL(fileURLWithPath: skillJSONPath, isDirectory: false)
    }
}

struct LearnedSkillSnapshot {
    let skills: [LearnedSkillSummary]
    let skillsById: [String: LearnedSkillSummary]
    let latestReviewBySkillId: [String: LearnedSkillReviewSummary]

    static let empty = LearnedSkillSnapshot(skills: [], skillsById: [:], latestReviewBySkillId: [:])
}

struct LearnedSkillRunResult {
    let totalSteps: Int
    let succeededSteps: Int
    let failedSteps: Int
    let blockedSteps: Int
    let logFilePath: String
    let qualityWarnings: [String]
}

enum LearnedSkillRepository {
    static func loadSnapshot() -> LearnedSkillSnapshot {
        let reviewBySkillId = LearnedSkillReviewRepository.loadLatestBySkillId()
        let pendingSkills = loadSkills(
            under: OpenStaffWorkspacePaths.skillsPendingDirectory,
            storageScope: .pending,
            reviewBySkillId: reviewBySkillId
        )
        let doneSkills = loadSkills(
            under: OpenStaffWorkspacePaths.skillsDoneDirectory,
            storageScope: .done,
            reviewBySkillId: reviewBySkillId
        )
        let merged = (pendingSkills + doneSkills).sorted { lhs, rhs in
            let lhsDate = lhs.createdAt ?? Date.distantPast
            let rhsDate = rhs.createdAt ?? Date.distantPast
            if lhsDate == rhsDate {
                return lhs.skillName < rhs.skillName
            }
            return lhsDate > rhsDate
        }

        var byId: [String: LearnedSkillSummary] = [:]
        byId.reserveCapacity(merged.count)
        for skill in merged {
            byId[skill.id] = skill
        }

        return LearnedSkillSnapshot(
            skills: merged,
            skillsById: byId,
            latestReviewBySkillId: reviewBySkillId
        )
    }

    static func deleteSkillDirectory(at directory: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }
        try fileManager.removeItem(at: directory)
    }

    private static func loadSkills(
        under root: URL,
        storageScope: LearnedSkillStorageScope,
        reviewBySkillId: [String: LearnedSkillReviewSummary]
    ) -> [LearnedSkillSummary] {
        let preflightValidator = SkillPreflightValidator()
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        let folders: [URL]
        do {
            folders = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        var skills: [LearnedSkillSummary] = []
        skills.reserveCapacity(folders.count)

        for folder in folders {
            let values = try? folder.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else {
                continue
            }

            let payloadURL = folder.appendingPathComponent("openstaff-skill.json", isDirectory: false)
            let preflight = preflightValidator.validateSkillDirectory(at: folder)
            let payload = try? preflightValidator.loadSkillBundle(from: folder)

            let skillId = "\(storageScope.rawValue)|\(folder.path)"
            let summary = LearnedSkillSummary(
                id: skillId,
                skillName: payload?.skillName ?? folder.lastPathComponent,
                taskId: payload?.taskId ?? "unknown-task",
                sessionId: payload?.sessionId ?? "unknown-session",
                knowledgeItemId: payload?.knowledgeItemId ?? "unknown-knowledge",
                skillDirectoryPath: folder.path,
                skillJSONPath: payloadURL.path,
                storageScope: storageScope,
                llmOutputAccepted: payload?.llmOutputAccepted ?? false,
                createdAt: payload.flatMap { OpenStaffDateFormatter.date(from: $0.createdAt) },
                review: reviewBySkillId[skillId],
                preflight: preflight
            )
            skills.append(summary)
        }

        return skills
    }
}

enum LearnedSkillReviewWriter {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static func append(_ entry: LearnedSkillReviewWriteEntry) throws {
        let directory = OpenStaffWorkspacePaths.skillsReviewDirectory
            .appendingPathComponent(OpenStaffDateFormatter.dayString(from: Date()), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("skill-review.jsonl", isDirectory: false)
        var payload = try encoder.encode(entry)
        payload.append(0x0A)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
            try handle.close()
        } else {
            try payload.write(to: fileURL, options: .atomic)
        }
    }
}

enum LearnedSkillReviewRepository {
    private static let decoder = JSONDecoder()

    static func loadLatestBySkillId() -> [String: LearnedSkillReviewSummary] {
        let files = listFiles(withExtension: "jsonl", under: OpenStaffWorkspacePaths.skillsReviewDirectory)
        guard !files.isEmpty else {
            return [:]
        }

        var latestBySkillId: [String: LearnedSkillReviewSummary] = [:]
        latestBySkillId.reserveCapacity(64)

        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                continue
            }
            for line in content.split(whereSeparator: \.isNewline) {
                guard let data = line.data(using: .utf8),
                      let record = try? decoder.decode(LearnedSkillReviewReadRecord.self, from: data),
                      let timestamp = OpenStaffDateFormatter.date(from: record.timestamp) else {
                    continue
                }

                let summary = LearnedSkillReviewSummary(
                    decision: record.decision,
                    timestamp: timestamp
                )

                if let existing = latestBySkillId[record.skillId] {
                    if summary.timestamp >= existing.timestamp {
                        latestBySkillId[record.skillId] = summary
                    }
                } else {
                    latestBySkillId[record.skillId] = summary
                }
            }
        }

        return latestBySkillId
    }

    private static func listFiles(withExtension pathExtension: String, under root: URL) -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == pathExtension {
            files.append(fileURL)
        }
        return files
    }
}

enum LearnedSkillRunner {
    static func run(
        skill: LearnedSkillSummary,
        emergencyStopActive: Bool,
        automaticExecution: Bool,
        teacherConfirmationGranted: Bool
    ) throws -> LearnedSkillRunResult {
        let data: Data
        do {
            data = try Data(contentsOf: skill.skillJSONURL)
        } catch {
            throw LearnedSkillRunnerError.skillPayloadReadFailed(skill.skillJSONPath)
        }

        let payload: SkillBundlePayload
        do {
            payload = try JSONDecoder().decode(SkillBundlePayload.self, from: data)
        } catch {
            throw LearnedSkillRunnerError.skillPayloadDecodeFailed(skill.skillJSONPath)
        }

        let preflight = SkillPreflightValidator().validate(
            payload: payload,
            skillDirectoryPath: skill.skillDirectoryPath
        )
        if preflight.status == .failed {
            throw LearnedSkillRunnerError.skillPreflightFailed(preflight.summary)
        }
        if preflight.requiresTeacherConfirmation {
            if automaticExecution {
                throw LearnedSkillRunnerError.teacherConfirmationRequired(preflight.summary)
            }
            if !teacherConfirmationGranted {
                throw LearnedSkillRunnerError.teacherConfirmationRequired(preflight.summary)
            }
        }

        let planSteps = payload.mappedOutput.executionPlan.steps
        guard !planSteps.isEmpty else {
            throw LearnedSkillRunnerError.skillStepEmpty(payload.skillName)
        }

        let traceId = "trace-skill-ui-run-\(UUID().uuidString.lowercased())"
        let executor = StudentSkillExecutor()
        let context = StudentExecutionContext(
            traceId: traceId,
            sessionId: payload.sessionId,
            taskId: payload.taskId,
            dryRun: false,
            emergencyStopActive: emergencyStopActive
        )
        let eventCoordinateIndex = loadEventCoordinateIndex(sessionId: payload.sessionId)
        let logWriter = StudentLoopLogWriter(logsRootDirectory: OpenStaffWorkspacePaths.logsDirectory)
        var latestLogURL = try logWriter.write(
            StudentLoopLogEntry(
                timestamp: OpenStaffDateFormatter.iso8601String(from: Date()),
                traceId: traceId,
                sessionId: payload.sessionId,
                taskId: payload.taskId,
                component: "student.skill.single-run",
                status: StudentLoopStatusCode.executionStarted.rawValue,
                message: "Manual UI run started for skill \(payload.skillName).",
                skillId: payload.skillName,
                skillName: payload.skillName,
                skillDirectoryPath: skill.skillDirectoryPath,
                sourceKnowledgeItemId: payload.knowledgeItemId
            )
        )

        var succeededSteps = 0
        var failedSteps = 0
        var blockedSteps = 0

        for (index, step) in planSteps.enumerated() {
            let plannedStep = StudentPlannedStep(
                planStepId: String(format: "single-step-%03d", index + 1),
                skillId: "\(payload.skillName)-\(step.stepId)",
                instruction: step.instruction,
                sourceKnowledgeItemId: payload.knowledgeItemId,
                sourceStepId: step.stepId,
                confidence: payload.mappedOutput.confidence
            )

            let executionResult = executor.execute(
                step: plannedStep,
                stepIndex: index,
                context: context
            )
            let finalized = finalizeStepExecution(
                base: executionResult,
                step: step,
                contextBundleId: payload.mappedOutput.context.appBundleId,
                eventCoordinateIndex: eventCoordinateIndex
            )

            let statusCode: String
            switch finalized.status {
            case .succeeded:
                statusCode = StudentLoopStatusCode.executionCompleted.rawValue
                succeededSteps += 1
            case .failed:
                statusCode = StudentLoopStatusCode.executionFailed.rawValue
                failedSteps += 1
            case .blocked:
                statusCode = StudentLoopStatusCode.executionFailed.rawValue
                blockedSteps += 1
            }

            latestLogURL = try logWriter.write(
                StudentLoopLogEntry(
                    timestamp: OpenStaffDateFormatter.iso8601String(from: Date()),
                    traceId: traceId,
                    sessionId: payload.sessionId,
                    taskId: payload.taskId,
                    component: "student.skill.single-run",
                    status: statusCode,
                    errorCode: finalized.errorCode?.rawValue,
                    message: finalized.output,
                    skillId: plannedStep.skillId,
                    planStepId: plannedStep.planStepId,
                    skillName: payload.skillName,
                    skillDirectoryPath: skill.skillDirectoryPath,
                    sourceKnowledgeItemId: payload.knowledgeItemId,
                    sourceStepId: step.stepId
                )
            )

            if finalized.status != .succeeded {
                break
            }
        }

        return LearnedSkillRunResult(
            totalSteps: planSteps.count,
            succeededSteps: succeededSteps,
            failedSteps: failedSteps,
            blockedSteps: blockedSteps,
            logFilePath: latestLogURL.path,
            qualityWarnings: evaluateQualityWarnings(
                payload: payload,
                planSteps: planSteps,
                eventCoordinateIndex: eventCoordinateIndex
            )
        )
    }

    private static func evaluateQualityWarnings(
        payload: SkillBundlePayload,
        planSteps: [SkillBundleExecutionStep],
        eventCoordinateIndex: [String: CGPoint]
    ) -> [String] {
        var warnings: [String] = []

        if !payload.llmOutputAccepted {
            warnings.append("LLM 输出未通过校验，当前技能由 fallback 规则生成。")
        }

        if planSteps.count <= 1 {
            warnings.append("技能仅包含 \(planSteps.count) 步，覆盖度可能不足。")
        }

        let unknownTargetSteps = planSteps.filter {
            $0.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || $0.target == "unknown"
        }
        if !unknownTargetSteps.isEmpty {
            warnings.append("存在 \(unknownTargetSteps.count) 个步骤 target=unknown，执行可能只做坐标点击。")
        }

        if eventCoordinateIndex.count <= 2 {
            warnings.append("教学会话仅采集到 \(eventCoordinateIndex.count) 条原始事件，难以复现完整任务。")
        }

        return warnings
    }

    private static func finalizeStepExecution(
        base: StudentStepExecutionResult,
        step: SkillBundleExecutionStep,
        contextBundleId: String,
        eventCoordinateIndex: [String: CGPoint]
    ) -> StudentStepExecutionResult {
        guard base.status == .succeeded else {
            return base
        }

        switch performAction(
            step: step,
            contextBundleId: contextBundleId,
            eventCoordinateIndex: eventCoordinateIndex
        ) {
        case .succeeded(let output):
            return StudentStepExecutionResult(
                planStepId: base.planStepId,
                skillId: base.skillId,
                status: .succeeded,
                startedAt: base.startedAt,
                finishedAt: OpenStaffDateFormatter.iso8601String(from: Date()),
                output: output,
                errorCode: nil
            )
        case .failed(let output):
            return StudentStepExecutionResult(
                planStepId: base.planStepId,
                skillId: base.skillId,
                status: .failed,
                startedAt: base.startedAt,
                finishedAt: OpenStaffDateFormatter.iso8601String(from: Date()),
                output: output,
                errorCode: .executionFailed
            )
        case .blocked(let output):
            return StudentStepExecutionResult(
                planStepId: base.planStepId,
                skillId: base.skillId,
                status: .blocked,
                startedAt: base.startedAt,
                finishedAt: OpenStaffDateFormatter.iso8601String(from: Date()),
                output: output,
                errorCode: .blockedAction
            )
        }
    }

    private static func performAction(
        step: SkillBundleExecutionStep,
        contextBundleId: String,
        eventCoordinateIndex: [String: CGPoint]
    ) -> LearnedSkillActionResult {
        let fallbackCoordinate = fallbackCoordinateFromSourceEvents(step.sourceEventIds, index: eventCoordinateIndex)
        return OpenStaffActionExecutor.executeAction(
            actionType: step.actionType,
            target: step.target,
            instruction: step.instruction,
            contextBundleId: contextBundleId,
            fallbackCoordinate: fallbackCoordinate
        )
    }

    private static func fallbackCoordinateFromSourceEvents(
        _ sourceEventIds: [String],
        index: [String: CGPoint]
    ) -> CGPoint? {
        for sourceEventId in sourceEventIds {
            if let point = index[sourceEventId] {
                return point
            }
        }
        return nil
    }

    private static func loadEventCoordinateIndex(sessionId: String) -> [String: CGPoint] {
        let root = OpenStaffWorkspacePaths.rawEventsDirectory
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else {
            return [:]
        }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        let decoder = JSONDecoder()
        var index: [String: CGPoint] = [:]
        index.reserveCapacity(128)

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            let fileName = fileURL.lastPathComponent
            if !isLikelySessionRawFile(fileName: fileName, sessionId: sessionId) {
                continue
            }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            for line in content.split(whereSeparator: \.isNewline) {
                guard let data = line.data(using: .utf8),
                      let event = try? decoder.decode(RawEvent.self, from: data),
                      event.sessionId == sessionId else {
                    continue
                }
                index[event.eventId] = CGPoint(
                    x: Double(event.pointer.x),
                    y: Double(event.pointer.y)
                )
            }
        }

        return index
    }

    private static func isLikelySessionRawFile(fileName: String, sessionId: String) -> Bool {
        if fileName == "\(sessionId).jsonl" {
            return true
        }
        if fileName.hasPrefix("\(sessionId)-r"), fileName.hasSuffix(".jsonl") {
            return true
        }
        return false
    }
}

enum LearnedSkillRunnerError: LocalizedError {
    case skillPayloadReadFailed(String)
    case skillPayloadDecodeFailed(String)
    case skillStepEmpty(String)
    case skillPreflightFailed(String)
    case teacherConfirmationRequired(String)

    var errorDescription: String? {
        switch self {
        case .skillPayloadReadFailed(let path):
            return "读取技能文件失败：\(path)"
        case .skillPayloadDecodeFailed(let path):
            return "解析技能文件失败：\(path)"
        case .skillStepEmpty(let skillName):
            return "技能 \(skillName) 不包含可执行步骤。"
        case .skillPreflightFailed(let summary):
            return "技能预检失败：\(summary)"
        case .teacherConfirmationRequired(let summary):
            return "技能命中安全门，需要老师确认后才能执行：\(summary)"
        }
    }
}

struct LearnedSkillReviewWriteEntry: Codable {
    let schemaVersion: String
    let reviewId: String
    let timestamp: String
    let reviewerRole: String
    let skillId: String
    let skillName: String
    let decision: LearnedSkillReviewDecision
    let skillDirectoryPath: String
    let note: String?

    init(
        reviewId: String,
        timestamp: String,
        skillId: String,
        skillName: String,
        decision: LearnedSkillReviewDecision,
        skillDirectoryPath: String,
        note: String? = nil
    ) {
        self.schemaVersion = "learned.skill.review.v0"
        self.reviewId = reviewId
        self.timestamp = timestamp
        self.reviewerRole = "teacher"
        self.skillId = skillId
        self.skillName = skillName
        self.decision = decision
        self.skillDirectoryPath = skillDirectoryPath
        self.note = note
    }
}

private struct LearnedSkillReviewReadRecord: Decodable {
    let skillId: String
    let timestamp: String
    let decision: LearnedSkillReviewDecision
}

enum LearnedSkillActionResult {
    case succeeded(String)
    case failed(String)
    case blocked(String)
}

enum OpenStaffWorkspacePaths {
    static var repositoryRoot: URL {
        let environment = ProcessInfo.processInfo.environment
        let fileManager = FileManager.default
        if let override = environment["OPENSTAFF_WORKSPACE_ROOT"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let overrideRoot = URL(fileURLWithPath: override, isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: overrideRoot.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return overrideRoot
            }
        }

        let seeds = workspaceRootSearchSeeds(fileManager: fileManager)
        for seed in seeds {
            if let matched = findWorkspaceRoot(startingAt: seed, maxDepth: 16, fileManager: fileManager) {
                return matched
            }
        }

        return URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    }

    private static func workspaceRootSearchSeeds(fileManager: FileManager) -> [URL] {
        let environment = ProcessInfo.processInfo.environment
        var seeds: [URL] = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        ]

        if let srcRoot = environment["SRCROOT"],
           !srcRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            seeds.append(URL(fileURLWithPath: srcRoot, isDirectory: true))
        }

        if let projectDir = environment["PROJECT_DIR"],
           !projectDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            seeds.append(URL(fileURLWithPath: projectDir, isDirectory: true))
        }

        // Compile-time source path is reliable when app runs from DerivedData.
        let sourceDirectory = URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
        seeds.append(sourceDirectory)

        if let executablePath = ProcessInfo.processInfo.arguments.first,
           !executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let executableDirectory = URL(fileURLWithPath: executablePath, isDirectory: false)
                .deletingLastPathComponent()
            seeds.append(executableDirectory)
        }

        if let bundleExecutableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            seeds.append(bundleExecutableDirectory)
        }

        var unique: [URL] = []
        var seen: Set<String> = []
        for seed in seeds {
            let key = seed.standardizedFileURL.path
            if seen.insert(key).inserted {
                unique.append(seed)
            }
        }
        return unique
    }

    private static func findWorkspaceRoot(
        startingAt start: URL,
        maxDepth: Int,
        fileManager: FileManager
    ) -> URL? {
        var candidate = start

        for _ in 0...maxDepth {
            if isWorkspaceRootCandidate(candidate, fileManager: fileManager) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                break
            }
            candidate = parent
        }

        return nil
    }

    private static func isWorkspaceRootCandidate(
        _ candidate: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let dataPath = candidate.appendingPathComponent("data", isDirectory: true).path
        let docsPath = candidate.appendingPathComponent("docs", isDirectory: true).path
        let promptScriptPath = candidate
            .appendingPathComponent("scripts/llm/render_knowledge_prompts.py", isDirectory: false)
            .path

        return fileManager.fileExists(atPath: dataPath)
            && fileManager.fileExists(atPath: docsPath)
            && fileManager.fileExists(atPath: promptScriptPath)
    }

    static var dataDirectory: URL {
        repositoryRoot.appendingPathComponent("data", isDirectory: true)
    }

    static var logsDirectory: URL {
        dataDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    static var knowledgeDirectory: URL {
        dataDirectory.appendingPathComponent("knowledge", isDirectory: true)
    }

    static var rawEventsDirectory: URL {
        dataDirectory.appendingPathComponent("raw-events", isDirectory: true)
    }

    static var taskChunksDirectory: URL {
        dataDirectory.appendingPathComponent("task-chunks", isDirectory: true)
    }

    static var feedbackDirectory: URL {
        dataDirectory.appendingPathComponent("feedback", isDirectory: true)
    }

    static var reportsDirectory: URL {
        dataDirectory.appendingPathComponent("reports", isDirectory: true)
    }

    static var preferencesDirectory: URL {
        dataDirectory.appendingPathComponent("preferences", isDirectory: true)
    }

    static var runtimeDirectory: URL {
        dataDirectory.appendingPathComponent("runtime", isDirectory: true)
    }

    static var llmDirectory: URL {
        dataDirectory.appendingPathComponent("llm", isDirectory: true)
    }

    static var llmOutputDirectory: URL {
        llmDirectory.appendingPathComponent("outputs", isDirectory: true)
    }

    static var llmManualDirectory: URL {
        llmDirectory.appendingPathComponent("manual", isDirectory: true)
    }

    static var llmReportDirectory: URL {
        llmDirectory.appendingPathComponent("reports", isDirectory: true)
    }

    static var skillsPendingDirectory: URL {
        dataDirectory
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("pending", isDirectory: true)
    }

    static var skillsDoneDirectory: URL {
        dataDirectory
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("done", isDirectory: true)
    }

    static var skillsReviewDirectory: URL {
        dataDirectory
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("reviews", isDirectory: true)
    }

    static var skillsRepairDirectory: URL {
        dataDirectory
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("repairs", isDirectory: true)
    }

    static func ensureDataDirectoryWritable() -> Bool {
        let fileManager = FileManager.default
        let dataPath = dataDirectory.path

        do {
            try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        } catch {
            return false
        }

        return fileManager.isWritableFile(atPath: dataPath)
    }
}

enum OpenStaffDateFormatter {
    static func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func displayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(from value: String) -> Date? {
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let fractionalDate = formatterWithFractional.date(from: value) {
            return fractionalDate
        }
        let formatterWithoutFractional = ISO8601DateFormatter()
        formatterWithoutFractional.formatOptions = [.withInternetDateTime]
        return formatterWithoutFractional.date(from: value)
    }
}

private extension OpenStaffMode {
    var color: Color {
        switch self {
        case .teaching:
            return .blue
        case .assist:
            return .orange
        case .student:
            return .green
        }
    }
}
