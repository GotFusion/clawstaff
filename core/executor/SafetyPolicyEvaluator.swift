import Foundation

public struct SafetyPolicyRules: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let lowConfidenceThreshold: Double
    public let highRiskKeywords: [String]
    public let highRiskRegexPatterns: [String]
    public let autoExecutionAllowlist: SafetyPolicyAllowlist
    public let sensitiveWindows: [SensitiveWindowRule]

    public init(
        schemaVersion: String = "openstaff.safety-rules.v1",
        lowConfidenceThreshold: Double = 0.80,
        highRiskKeywords: [String] = [
            "删除",
            "移除",
            "支付",
            "付款",
            "转账",
            "系统设置",
            "格式化",
            "抹掉",
            "重置",
            "sudo",
            "rm -rf"
        ],
        highRiskRegexPatterns: [String] = [
            #"(?i)\brm\s+-rf\b"#,
            #"(?i)\bsudo\s+"#,
            #"(?i)\bshutdown\b|\breboot\b"#,
            #"(?i)\bdd\s+if="#
        ],
        autoExecutionAllowlist: SafetyPolicyAllowlist = SafetyPolicyAllowlist(),
        sensitiveWindows: [SensitiveWindowRule] = SafetyPolicyRules.defaultSensitiveWindows
    ) {
        self.schemaVersion = schemaVersion
        self.lowConfidenceThreshold = lowConfidenceThreshold
        self.highRiskKeywords = highRiskKeywords
        self.highRiskRegexPatterns = highRiskRegexPatterns
        self.autoExecutionAllowlist = autoExecutionAllowlist
        self.sensitiveWindows = sensitiveWindows
    }

    public static let fallback = SafetyPolicyRules()

    public static let defaultSensitiveWindows: [SensitiveWindowRule] = [
        SensitiveWindowRule(
            tag: "payment",
            appBundleIds: [
                "com.alipay.client",
                "com.tencent.xinWeChat",
                "com.apple.Passbook"
            ],
            windowTitleKeywords: [
                "支付",
                "付款",
                "收银台",
                "订单支付",
                "checkout",
                "billing",
                "payment"
            ],
            windowTitleRegexPatterns: [
                #"(?i)\b(checkout|payment|billing)\b"#
            ]
        ),
        SensitiveWindowRule(
            tag: "system_settings",
            appBundleIds: [
                "com.apple.systempreferences",
                "com.apple.systemsettings"
            ],
            windowTitleKeywords: [
                "系统设置",
                "System Settings",
                "隐私与安全性",
                "Privacy & Security"
            ],
            windowTitleRegexPatterns: [
                #"(?i)\b(system settings|privacy\s*&\s*security)\b"#
            ]
        ),
        SensitiveWindowRule(
            tag: "password_manager",
            appBundleIds: [
                "com.1password.1password",
                "com.1password.1password7",
                "com.bitwarden.desktop",
                "com.lastpass.LastPass",
                "com.apple.keychainaccess"
            ],
            windowTitleKeywords: [
                "密码",
                "Password",
                "密码库",
                "Vault",
                "1Password",
                "Bitwarden",
                "钥匙串"
            ],
            windowTitleRegexPatterns: [
                #"(?i)\b(password|vault|keychain|1password|bitwarden)\b"#
            ]
        ),
        SensitiveWindowRule(
            tag: "privacy_permission_popup",
            appBundleIds: [],
            windowTitleKeywords: [
                "辅助功能",
                "屏幕录制",
                "完全磁盘访问权限",
                "Would Like to Access",
                "Would Like to Control",
                "Privacy",
                "Allow",
                "Don't Allow",
                "不允许",
                "允许"
            ],
            windowTitleRegexPatterns: [
                #"(?i)(would like to (access|control)|screen recording|accessibility|privacy)"#
            ]
        )
    ]
}

public struct SafetyPolicyAllowlist: Codable, Equatable, Sendable {
    public let apps: [String]
    public let tasks: [String]
    public let skills: [String]

    public init(
        apps: [String] = [],
        tasks: [String] = [],
        skills: [String] = []
    ) {
        self.apps = apps
        self.tasks = tasks
        self.skills = skills
    }
}

public struct SensitiveWindowRule: Codable, Equatable, Sendable {
    public let tag: String
    public let appBundleIds: [String]
    public let windowTitleKeywords: [String]
    public let windowTitleRegexPatterns: [String]

    public init(
        tag: String,
        appBundleIds: [String] = [],
        windowTitleKeywords: [String] = [],
        windowTitleRegexPatterns: [String] = []
    ) {
        self.tag = tag
        self.appBundleIds = appBundleIds
        self.windowTitleKeywords = windowTitleKeywords
        self.windowTitleRegexPatterns = windowTitleRegexPatterns
    }
}

public struct SafetyPolicyContext: Sendable {
    public let taskId: String?
    public let skillName: String
    public let contextAppBundleId: String
    public let targetAppBundleIds: [String]
    public let windowTitles: [String]
    public let actionType: String
    public let instruction: String
    public let target: String
    public let confidence: Double
    public let locatorStatus: SkillPreflightLocatorStatus
    public let planRequiresTeacherConfirmation: Bool
    public let highRiskKeywordsOverride: [String]
    public let highRiskRegexPatternsOverride: [String]
    public let lowConfidenceThresholdOverride: Double?

    public init(
        taskId: String?,
        skillName: String,
        contextAppBundleId: String,
        targetAppBundleIds: [String],
        windowTitles: [String],
        actionType: String,
        instruction: String,
        target: String,
        confidence: Double,
        locatorStatus: SkillPreflightLocatorStatus,
        planRequiresTeacherConfirmation: Bool,
        highRiskKeywordsOverride: [String] = [],
        highRiskRegexPatternsOverride: [String] = [],
        lowConfidenceThresholdOverride: Double? = nil
    ) {
        self.taskId = taskId
        self.skillName = skillName
        self.contextAppBundleId = contextAppBundleId
        self.targetAppBundleIds = targetAppBundleIds
        self.windowTitles = windowTitles
        self.actionType = actionType
        self.instruction = instruction
        self.target = target
        self.confidence = confidence
        self.locatorStatus = locatorStatus
        self.planRequiresTeacherConfirmation = planRequiresTeacherConfirmation
        self.highRiskKeywordsOverride = highRiskKeywordsOverride
        self.highRiskRegexPatternsOverride = highRiskRegexPatternsOverride
        self.lowConfidenceThresholdOverride = lowConfidenceThresholdOverride
    }
}

public struct SafetyPolicyDecision: Sendable {
    public let highRisk: Bool
    public let lowConfidence: Bool
    public let lowReproducibility: Bool
    public let sensitiveWindowTags: [String]
    public let matchedAllowlistScopes: [String]
    public let requiresTeacherConfirmation: Bool
    public let blocksAutoExecution: Bool
    public let issues: [SkillPreflightIssue]

    public init(
        highRisk: Bool,
        lowConfidence: Bool,
        lowReproducibility: Bool,
        sensitiveWindowTags: [String],
        matchedAllowlistScopes: [String],
        requiresTeacherConfirmation: Bool,
        blocksAutoExecution: Bool,
        issues: [SkillPreflightIssue]
    ) {
        self.highRisk = highRisk
        self.lowConfidence = lowConfidence
        self.lowReproducibility = lowReproducibility
        self.sensitiveWindowTags = sensitiveWindowTags
        self.matchedAllowlistScopes = matchedAllowlistScopes
        self.requiresTeacherConfirmation = requiresTeacherConfirmation
        self.blocksAutoExecution = blocksAutoExecution
        self.issues = issues
    }
}

public struct SafetyPolicyEvaluator {
    private let rules: SafetyPolicyRules

    public init(
        rules: SafetyPolicyRules? = nil,
        rulesPath: String? = nil,
        fileManager: FileManager = .default
    ) {
        if let rules {
            self.rules = rules
        } else if let loadedRules = Self.loadRules(rulesPath: rulesPath, fileManager: fileManager) {
            self.rules = loadedRules
        } else {
            self.rules = .fallback
        }
    }

    public func evaluate(
        stepId: String,
        context: SafetyPolicyContext
    ) -> SafetyPolicyDecision {
        let threshold = normalizedThreshold(context.lowConfidenceThresholdOverride ?? rules.lowConfidenceThreshold)
        let highRiskKeywords = deduplicated(rules.highRiskKeywords + context.highRiskKeywordsOverride)
        let highRiskRegexPatterns = deduplicated(rules.highRiskRegexPatterns + context.highRiskRegexPatternsOverride)
        let sensitiveWindowTags = matchedSensitiveWindowTags(context: context)
        let lowConfidence = context.confidence < threshold
        let lowReproducibility = context.locatorStatus == .degraded
        let highRisk = isHighRisk(
            context: context,
            keywords: highRiskKeywords,
            regexPatterns: highRiskRegexPatterns
        ) || !sensitiveWindowTags.isEmpty

        let matchedAllowlistScopes = matchedAllowlistScopes(context: context)
        let allowlisted = !matchedAllowlistScopes.isEmpty
        let blocksAutoExecution = !allowlisted
            && (!sensitiveWindowTags.isEmpty || (highRisk && lowConfidence && lowReproducibility))
        let requiresTeacherConfirmation = context.planRequiresTeacherConfirmation
            || (!allowlisted && (highRisk || lowConfidence || lowReproducibility))

        var issues: [SkillPreflightIssue] = []
        if lowConfidence {
            issues.append(
                SkillPreflightIssue(
                    severity: .warning,
                    code: .lowConfidence,
                    message: "步骤 \(stepId) 置信度 \(String(format: "%.2f", context.confidence)) 低于阈值 \(String(format: "%.2f", threshold))，需要老师确认。",
                    stepId: stepId
                )
            )
        }

        if highRisk {
            issues.append(
                SkillPreflightIssue(
                    severity: .warning,
                    code: .highRiskAction,
                    message: "步骤 \(stepId) 被识别为高风险动作，需要老师确认。",
                    stepId: stepId
                )
            )
        }

        if lowReproducibility {
            issues.append(
                SkillPreflightIssue(
                    severity: .warning,
                    code: .lowReproducibility,
                    message: "步骤 \(stepId) 复现度较低（locatorStatus=\(context.locatorStatus.rawValue)），默认不能自动执行。",
                    stepId: stepId
                )
            )
        }

        if !sensitiveWindowTags.isEmpty {
            issues.append(
                SkillPreflightIssue(
                    severity: .warning,
                    code: .sensitiveWindow,
                    message: "步骤 \(stepId) 命中敏感窗口：\(sensitiveWindowTags.joined(separator: ", "))。",
                    stepId: stepId
                )
            )
        }

        if blocksAutoExecution {
            issues.append(
                SkillPreflightIssue(
                    severity: .warning,
                    code: .autoExecutionBlockedByPolicy,
                    message: "步骤 \(stepId) 命中“低置信 + 高风险 + 低复现度”或敏感窗口策略，默认禁止学生模式自动直跑。",
                    stepId: stepId
                )
            )
        }

        return SafetyPolicyDecision(
            highRisk: highRisk,
            lowConfidence: lowConfidence,
            lowReproducibility: lowReproducibility,
            sensitiveWindowTags: sensitiveWindowTags,
            matchedAllowlistScopes: matchedAllowlistScopes,
            requiresTeacherConfirmation: requiresTeacherConfirmation,
            blocksAutoExecution: blocksAutoExecution,
            issues: issues
        )
    }

    private func isHighRisk(
        context: SafetyPolicyContext,
        keywords: [String],
        regexPatterns: [String]
    ) -> Bool {
        let actionType = normalized(context.actionType)
        let targetAppBundleIds = deduplicated(context.targetAppBundleIds + [context.contextAppBundleId])
        let joinedText = "\(context.instruction)\n\(context.target)"

        if targetAppBundleIds.contains(where: { $0.caseInsensitiveCompare("com.apple.Terminal") == .orderedSame }),
           actionType == "input" {
            return true
        }

        if actionType == "openapp",
           let bundleId = parseBundleTarget(context.target),
           bundleId.localizedCaseInsensitiveContains("systemsettings")
            || bundleId.localizedCaseInsensitiveContains("systempreferences") {
            return true
        }

        for keyword in keywords where !keyword.isEmpty {
            if joinedText.localizedCaseInsensitiveContains(keyword) {
                return true
            }
        }

        for pattern in regexPatterns where !pattern.isEmpty {
            if joinedText.range(of: pattern, options: [.regularExpression]) != nil {
                return true
            }
        }

        return false
    }

    private func matchedSensitiveWindowTags(context: SafetyPolicyContext) -> [String] {
        let bundleIds = Set(
            deduplicated(context.targetAppBundleIds + [context.contextAppBundleId]).map {
                normalized($0).lowercased()
            }
        )
        let windowTexts = context.windowTitles
            .map { normalized($0) }
            .filter { !$0.isEmpty }

        var tags: [String] = []
        for rule in rules.sensitiveWindows {
            let matchedByBundle = rule.appBundleIds.contains { bundleIds.contains(normalized($0).lowercased()) }
            let matchedByKeyword = rule.windowTitleKeywords.contains { keyword in
                windowTexts.contains { $0.localizedCaseInsensitiveContains(keyword) }
            }
            let matchedByRegex = rule.windowTitleRegexPatterns.contains { pattern in
                windowTexts.contains { $0.range(of: pattern, options: [.regularExpression]) != nil }
            }

            if matchedByBundle || matchedByKeyword || matchedByRegex {
                let normalizedTag = normalized(rule.tag)
                if !normalizedTag.isEmpty, !tags.contains(normalizedTag) {
                    tags.append(normalizedTag)
                }
            }
        }
        return tags
    }

    private func matchedAllowlistScopes(context: SafetyPolicyContext) -> [String] {
        var values: [String] = []
        let normalizedBundleIds = deduplicated(context.targetAppBundleIds + [context.contextAppBundleId])
        for bundleId in normalizedBundleIds {
            if rules.autoExecutionAllowlist.apps.contains(where: { normalized($0).caseInsensitiveCompare(bundleId) == .orderedSame }) {
                values.append("app:\(bundleId)")
            }
        }

        if let taskId = normalizedOptional(context.taskId),
           rules.autoExecutionAllowlist.tasks.contains(where: { normalized($0) == taskId }) {
            values.append("task:\(taskId)")
        }

        let skillName = normalized(context.skillName)
        if !skillName.isEmpty,
           rules.autoExecutionAllowlist.skills.contains(where: { normalized($0) == skillName }) {
            values.append("skill:\(skillName)")
        }

        return deduplicated(values)
    }

    private static func loadRules(
        rulesPath: String?,
        fileManager: FileManager
    ) -> SafetyPolicyRules? {
        let candidateURLs: [URL?] = [
            rulesPath.map { URL(fileURLWithPath: $0, isDirectory: false) },
            defaultRulesURL(fileManager: fileManager)
        ]

        let decoder = JSONDecoder()
        for candidateURL in candidateURLs {
            guard let candidateURL else {
                continue
            }
            guard fileManager.fileExists(atPath: candidateURL.path) else {
                continue
            }
            guard let data = try? Data(contentsOf: candidateURL) else {
                continue
            }
            if let rules = try? decoder.decode(SafetyPolicyRules.self, from: data) {
                return rules
            }
        }
        return nil
    }

    private static func defaultRulesURL(fileManager: FileManager) -> URL? {
        let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        if let found = searchUpward(from: currentDirectoryURL, fileManager: fileManager) {
            return found
        }

        let sourceURL = URL(fileURLWithPath: #filePath, isDirectory: false).deletingLastPathComponent()
        return searchUpward(from: sourceURL, fileManager: fileManager)
    }

    private static func searchUpward(
        from startURL: URL,
        fileManager: FileManager
    ) -> URL? {
        var cursor = startURL
        for _ in 0..<8 {
            let candidate = cursor.appendingPathComponent("config/safety-rules.yaml", isDirectory: false)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path {
                break
            }
            cursor = parent
        }
        return nil
    }

    private func normalizedThreshold(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private func parseBundleTarget(_ target: String) -> String? {
        let normalizedTarget = normalized(target)
        guard normalizedTarget.hasPrefix("bundle:") else {
            return nil
        }
        let value = String(normalizedTarget.dropFirst("bundle:".count))
        return value.isEmpty ? nil : value
    }

    private func normalizedOptional(_ value: String?) -> String? {
        let normalizedValue = normalized(value)
        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    private func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func deduplicated(_ values: [String]) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        for value in values {
            let normalizedValue = normalized(value)
            guard !normalizedValue.isEmpty else {
                continue
            }
            let lowercased = normalizedValue.lowercased()
            if seen.insert(lowercased).inserted {
                ordered.append(normalizedValue)
            }
        }
        return ordered
    }
}
