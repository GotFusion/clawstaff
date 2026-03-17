import SwiftUI

struct LearningPrivacyPanel: View {
    @ObservedObject var dashboardViewModel: OpenStaffDashboardViewModel
    @State private var appDisplayName = ""
    @State private var appBundleId = ""
    @State private var appName = ""
    @State private var windowRuleDisplayName = ""
    @State private var windowRulePattern = ""
    @State private var windowRuleMatchType: LearningWindowTitleMatchType = .contains

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            temporaryPauseSection
            Divider()
            appExclusionSection
            Divider()
            windowTitleExclusionSection
            Divider()
            sensitiveSceneSection
        }
        .padding(.top, 4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("隐私规则持久化路径")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dashboardViewModel.learningPrivacyConfigurationPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button("重新加载") {
                    dashboardViewModel.reloadLearningPrivacyConfiguration()
                }
                .buttonStyle(.bordered)
            }

            Text("OpenStaff 自身界面始终自动排除，不需要手动添加。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let statusMessage = dashboardViewModel.learningPrivacyStatusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(dashboardViewModel.learningPrivacyStatusSucceeded ? .green : .red)
            }
        }
    }

    private var temporaryPauseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("15 分钟临时暂停")
                .font(.headline)

            Text(dashboardViewModel.learningTemporaryPauseDescription)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("暂停 15 分钟") {
                    dashboardViewModel.pauseLearningCaptureForFifteenMinutes()
                }
                .buttonStyle(.borderedProminent)

                Button("立即恢复") {
                    dashboardViewModel.clearLearningTemporaryPause()
                }
                .buttonStyle(.bordered)
                .disabled(!dashboardViewModel.learningPrivacyConfiguration.isTemporaryPauseActive(at: Date()))
            }
        }
    }

    private var appExclusionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App 排除名单")
                .font(.headline)

            if dashboardViewModel.learningAppExclusions.isEmpty {
                Text("暂无自定义 app 排除规则。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(dashboardViewModel.learningAppExclusions) { rule in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.resolvedDisplayName)
                                    .font(.callout.weight(.semibold))
                                if !rule.bundleId.isEmpty {
                                    Text(rule.bundleId)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                if !rule.appName.isEmpty, rule.appName != rule.resolvedDisplayName {
                                    Text("appName: \(rule.appName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Button("移除") {
                                dashboardViewModel.removeLearningAppExclusion(id: rule.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button("排除当前前台 app") {
                    dashboardViewModel.addCurrentAppToLearningExclusions()
                }
                .buttonStyle(.bordered)
                .disabled(currentAppIsUnknown)

                Text(currentAppSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("显示名称（可选）", text: $appDisplayName)
                TextField("bundle id（推荐）", text: $appBundleId)
                TextField("app 名称（可选）", text: $appName)

                Button("添加 app 排除规则") {
                    dashboardViewModel.addLearningAppExclusion(
                        displayName: appDisplayName,
                        bundleId: appBundleId,
                        appName: appName
                    )
                    appDisplayName = ""
                    appBundleId = ""
                    appName = ""
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var windowTitleExclusionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("窗口标题排除规则")
                .font(.headline)

            if dashboardViewModel.learningWindowTitleExclusions.isEmpty {
                Text("暂无窗口标题排除规则。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(dashboardViewModel.learningWindowTitleExclusions) { rule in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.resolvedDisplayName)
                                    .font(.callout.weight(.semibold))
                                Text("\(rule.matchType.displayName) · \(rule.pattern)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button("移除") {
                                dashboardViewModel.removeLearningWindowTitleExclusion(id: rule.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button("按当前窗口标题添加") {
                    dashboardViewModel.addCurrentWindowTitleToLearningExclusions(
                        matchType: windowRuleMatchType
                    )
                }
                .buttonStyle(.bordered)
                .disabled(currentWindowTitle.isEmpty)

                Text(currentWindowTitle.isEmpty ? "当前没有可用窗口标题。" : "当前窗口：\(currentWindowTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("规则名称（可选）", text: $windowRuleDisplayName)
                TextField("标题关键词或正则", text: $windowRulePattern)

                Picker("匹配方式", selection: $windowRuleMatchType) {
                    ForEach(LearningWindowTitleMatchType.allCases, id: \.self) { matchType in
                        Text(matchType.displayName).tag(matchType)
                    }
                }
                .pickerStyle(.segmented)

                Button("添加窗口标题规则") {
                    dashboardViewModel.addLearningWindowTitleExclusion(
                        displayName: windowRuleDisplayName,
                        pattern: windowRulePattern,
                        matchType: windowRuleMatchType
                    )
                    windowRuleDisplayName = ""
                    windowRulePattern = ""
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var sensitiveSceneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "敏感场景自动静默",
                isOn: Binding(
                    get: { dashboardViewModel.learningPrivacyConfiguration.sensitiveSceneAutoMuteEnabled },
                    set: { dashboardViewModel.setSensitiveSceneAutoMuteEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .font(.headline)

            Text("第一版覆盖密码输入、支付、隐私授权、医疗、金融。命中后会停止 learning capture，不再继续落盘。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(dashboardViewModel.learningSensitiveSceneRules) { rule in
                    Toggle(
                        isOn: Binding(
                            get: {
                                dashboardViewModel.learningPrivacyConfiguration.isSensitiveSceneEnabled(rule.id)
                            },
                            set: { isEnabled in
                                dashboardViewModel.setSensitiveSceneRule(rule.id, enabled: isEnabled)
                            }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.displayName)
                                .font(.callout.weight(.semibold))
                            Text(rulePreviewText(rule))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .disabled(!dashboardViewModel.learningPrivacyConfiguration.sensitiveSceneAutoMuteEnabled)
                }
            }
        }
    }

    private var currentAppIsUnknown: Bool {
        let currentApp = dashboardViewModel.learningSessionState.currentApp
        return currentApp.appBundleId == LearningSurfaceAppContext.unknown.appBundleId
            && currentApp.appName == LearningSurfaceAppContext.unknown.appName
    }

    private var currentAppSummary: String {
        let currentApp = dashboardViewModel.learningSessionState.currentApp
        if currentAppIsUnknown {
            return "当前 app 上下文不可用。"
        }
        return "\(currentApp.appName) (\(currentApp.appBundleId))"
    }

    private var currentWindowTitle: String {
        dashboardViewModel.learningSessionState.currentApp.windowTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func rulePreviewText(_ rule: SensitiveSceneRule) -> String {
        let samples = Array(rule.windowTitleKeywords.prefix(4))
        if samples.isEmpty {
            return "按 app bundle 或窗口正则命中。"
        }
        return "示例关键词：\(samples.joined(separator: "、"))"
    }
}
