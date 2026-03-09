import SwiftUI

struct OpenStaffPrototypeView: View {
    @StateObject private var viewModel = OpenStaffPrototypeViewModel()

    var body: some View {
        ZStack {
            OpenStaffPrototypeTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroSection

                    HStack(alignment: .top, spacing: 14) {
                        modeSection
                        commandSection
                    }

                    HStack(alignment: .top, spacing: 14) {
                        timelineSection
                        knowledgeSection
                    }

                    logSection
                }
                .padding(22)
            }
        }
    }

    private var heroSection: some View {
        OpenStaffPrototypeCard(title: "OpenStaff 原型", subtitle: "老师-学生个人助理 · 界面原型 v0") {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.mode.displayName)
                        .font(.title2.weight(.semibold))
                    Text("下一步建议：\(viewModel.nextActionSuggestion)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("预测置信度")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(viewModel.predictionConfidence * 100))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    ProgressView(value: viewModel.predictionConfidence, total: 1)
                        .frame(width: 150)
                        .tint(OpenStaffPrototypeTheme.accent)
                }
            }
        }
    }

    private var modeSection: some View {
        OpenStaffPrototypeCard(title: "模式切换", subtitle: "教学 / 辅助 / 学生") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(OpenStaffPrototypeMode.allCases, id: \.self) { mode in
                    Button {
                        viewModel.switchMode(mode)
                    } label: {
                        HStack {
                            Circle()
                                .fill(mode == viewModel.mode ? OpenStaffPrototypeTheme.accent : Color.secondary.opacity(0.35))
                                .frame(width: 9, height: 9)
                            Text(mode.displayName)
                                .font(.headline)
                            Spacer()
                            Text(mode == viewModel.mode ? "当前" : "切换")
                                .font(.caption)
                                .foregroundStyle(mode == viewModel.mode ? OpenStaffPrototypeTheme.accent : .secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(mode == viewModel.mode ? OpenStaffPrototypeTheme.accent.opacity(0.12) : Color.white.opacity(0.45))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 320)
    }

    private var commandSection: some View {
        OpenStaffPrototypeCard(title: "指令面板", subtitle: "快速演示主链路") {
            VStack(alignment: .leading, spacing: 10) {
                prototypeActionButton(
                    title: "开始教学录制",
                    subtitle: "模拟老师点击行为采集与切片",
                    action: viewModel.startTeachingCapture
                )
                prototypeActionButton(
                    title: "模拟辅助预测",
                    subtitle: "预测下一步并触发确认弹窗",
                    action: viewModel.simulateAssistPrediction
                )
                prototypeActionButton(
                    title: "运行学生模式",
                    subtitle: "根据知识条目自动执行并生成报告",
                    action: viewModel.runStudentAutopilot
                )
            }
        }
    }

    private func prototypeActionButton(
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(OpenStaffPrototypeTheme.secondaryAccent.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
    }

    private var timelineSection: some View {
        OpenStaffPrototypeCard(title: "执行流程", subtitle: "观察 -> 学习 -> 建议 -> 执行") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.timelineItems) { item in
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.status.color)
                            .frame(width: 6, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.headline)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.status.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(item.status.color.opacity(0.18), in: Capsule())
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.45))
                    )
                }
            }
        }
    }

    private var knowledgeSection: some View {
        OpenStaffPrototypeCard(title: "知识摘要", subtitle: "当前学习到的操作结构") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("目标", value: "在 Safari 中复现点击流程")
                LabeledContent("步骤数量", value: "2")
                LabeledContent("主应用", value: "Safari / com.apple.Safari")
                Divider()
                Text("关键约束")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(viewModel.constraints, id: \.self) { constraint in
                    Text("• \(constraint)")
                        .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 360)
    }

    private var logSection: some View {
        OpenStaffPrototypeCard(title: "实时事件流", subtitle: "原型交互日志") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.activityLogs, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct OpenStaffPrototypeCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

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
                .fill(OpenStaffPrototypeTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
    }
}

private enum OpenStaffPrototypeTheme {
    static let accent = Color(red: 0.08, green: 0.46, blue: 0.97)
    static let secondaryAccent = Color(red: 0.06, green: 0.74, blue: 0.62)
    static let cardFill = Color.white.opacity(0.72)
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.93, green: 0.97, blue: 1.00),
            Color(red: 0.86, green: 0.95, blue: 0.95),
            Color(red: 0.92, green: 0.92, blue: 0.98)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private enum OpenStaffPrototypeMode: String, CaseIterable {
    case teaching
    case assist
    case student

    var displayName: String {
        switch self {
        case .teaching:
            return "教学模式"
        case .assist:
            return "辅助模式"
        case .student:
            return "学生模式"
        }
    }
}

private enum OpenStaffTimelineStatus {
    case idle
    case active
    case done

    var displayName: String {
        switch self {
        case .idle:
            return "待执行"
        case .active:
            return "进行中"
        case .done:
            return "完成"
        }
    }

    var color: Color {
        switch self {
        case .idle:
            return Color.secondary.opacity(0.55)
        case .active:
            return OpenStaffPrototypeTheme.accent
        case .done:
            return OpenStaffPrototypeTheme.secondaryAccent
        }
    }
}

private struct OpenStaffTimelineItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    var status: OpenStaffTimelineStatus
}

@MainActor
private final class OpenStaffPrototypeViewModel: ObservableObject {
    @Published var mode: OpenStaffPrototypeMode = .teaching
    @Published var predictionConfidence: Double = 0.78
    @Published var nextActionSuggestion: String = "等待老师输入第一步操作"
    @Published var timelineItems: [OpenStaffTimelineItem] = [
        OpenStaffTimelineItem(id: "capture", title: "捕获点击事件", detail: "监听坐标与前台应用上下文", status: .idle),
        OpenStaffTimelineItem(id: "knowledge", title: "归纳知识条目", detail: "切片任务并生成结构化步骤", status: .idle),
        OpenStaffTimelineItem(id: "assist", title: "辅助模式建议", detail: "预测下一步并等待老师确认", status: .idle),
        OpenStaffTimelineItem(id: "student", title: "学生模式执行", detail: "根据知识自动执行并回写报告", status: .idle)
    ]
    @Published var activityLogs: [String] = [
        "09:00:00 READY  Prototype initialized."
    ]

    let constraints: [String] = [
        "执行前前台应用必须匹配",
        "高风险动作必须人工确认",
        "坐标目标可能漂移，需复核"
    ]

    func switchMode(_ newMode: OpenStaffPrototypeMode) {
        mode = newMode
        appendLog("MODE   Switched to \(newMode.displayName)")
    }

    func startTeachingCapture() {
        mode = .teaching
        predictionConfidence = 0.42
        nextActionSuggestion = "正在学习老师操作习惯..."
        setTimelineStatus(["capture": .active, "knowledge": .idle, "assist": .idle, "student": .idle])
        appendLog("TEACH  Capture started, raw events streaming.")
    }

    func simulateAssistPrediction() {
        mode = .assist
        predictionConfidence = 0.82
        nextActionSuggestion = "建议执行：点击 Safari 标签页中的目标按钮"
        setTimelineStatus(["capture": .done, "knowledge": .done, "assist": .active, "student": .idle])
        appendLog("ASSIST Predicted next step, waiting for confirmation.")
    }

    func runStudentAutopilot() {
        mode = .student
        predictionConfidence = 0.9
        nextActionSuggestion = "学生模式执行中：将生成审阅报告"
        setTimelineStatus(["capture": .done, "knowledge": .done, "assist": .done, "student": .active])
        appendLog("AUTO   Student mode running by knowledge plan.")
        appendLog("AUTO   Review report generated for teacher approval.")
    }

    private func setTimelineStatus(_ mapping: [String: OpenStaffTimelineStatus]) {
        timelineItems = timelineItems.map { item in
            guard let status = mapping[item.id] else {
                return item
            }
            return OpenStaffTimelineItem(id: item.id, title: item.title, detail: item.detail, status: status)
        }
    }

    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let line = "\(formatter.string(from: Date())) \(message)"
        activityLogs.insert(line, at: 0)
        activityLogs = Array(activityLogs.prefix(8))
    }
}
