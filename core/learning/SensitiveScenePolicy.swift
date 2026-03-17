import Foundation

public struct SensitiveSceneRule: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let appBundleIds: [String]
    public let windowTitleKeywords: [String]
    public let windowTitleRegexPatterns: [String]

    public init(
        id: String,
        displayName: String,
        appBundleIds: [String] = [],
        windowTitleKeywords: [String] = [],
        windowTitleRegexPatterns: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.appBundleIds = appBundleIds
        self.windowTitleKeywords = windowTitleKeywords
        self.windowTitleRegexPatterns = windowTitleRegexPatterns
    }
}

public struct SensitiveScenePolicy: Sendable {
    public let rules: [SensitiveSceneRule]

    public init(rules: [SensitiveSceneRule] = SensitiveScenePolicy.defaultLearningRules) {
        self.rules = rules
    }

    public static let defaultLearningRules: [SensitiveSceneRule] = [
        SensitiveSceneRule(
            id: "password_entry",
            displayName: "密码输入 / 登录验证",
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
                "Passkey",
                "登录",
                "Sign In",
                "Log In",
                "验证",
                "验证码",
                "OTP",
                "2FA",
                "钥匙串"
            ],
            windowTitleRegexPatterns: [
                #"(?i)\b(sign in|log in|password|passkey|verification|otp|2fa|keychain)\b"#
            ]
        ),
        SensitiveSceneRule(
            id: "payment",
            displayName: "支付 / 付款",
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
        SensitiveSceneRule(
            id: "privacy_authorization",
            displayName: "隐私授权 / 系统权限",
            appBundleIds: [
                "com.apple.systempreferences",
                "com.apple.systemsettings"
            ],
            windowTitleKeywords: [
                "系统设置",
                "System Settings",
                "隐私与安全性",
                "Privacy & Security",
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
                #"(?i)\b(system settings|privacy\s*&\s*security)\b"#,
                #"(?i)(would like to (access|control)|screen recording|accessibility|privacy)"#
            ]
        ),
        SensitiveSceneRule(
            id: "medical",
            displayName: "医疗 / 健康信息",
            windowTitleKeywords: [
                "医疗",
                "病历",
                "就诊",
                "诊断",
                "检验",
                "报告",
                "处方",
                "医保",
                "medical",
                "patient",
                "clinic",
                "hospital",
                "health"
            ],
            windowTitleRegexPatterns: [
                #"(?i)\b(medical|patient|clinic|hospital|health record|lab result|prescription)\b"#
            ]
        ),
        SensitiveSceneRule(
            id: "financial",
            displayName: "金融 / 账单信息",
            windowTitleKeywords: [
                "银行",
                "证券",
                "基金",
                "理财",
                "账单",
                "对账单",
                "发票",
                "交易",
                "finance",
                "financial",
                "bank",
                "banking",
                "brokerage",
                "statement",
                "portfolio",
                "tax"
            ],
            windowTitleRegexPatterns: [
                #"(?i)\b(bank|banking|finance|financial|brokerage|portfolio|statement|invoice|tax)\b"#
            ]
        )
    ]

    public static var defaultEnabledRuleIds: [String] {
        defaultLearningRules.map(\.id)
    }

    public func match(
        for app: LearningSurfaceAppContext,
        enabledRuleIds: [String]? = nil
    ) -> LearningStatusRuleMatch? {
        let enabledIds = Set((enabledRuleIds ?? Self.defaultEnabledRuleIds).map(Self.normalized))
        let bundleId = Self.normalized(app.appBundleId)
        let windowTitle = app.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        for rule in rules where enabledIds.contains(Self.normalized(rule.id)) {
            if matches(rule: rule, bundleId: bundleId, windowTitle: windowTitle) {
                return LearningStatusRuleMatch(
                    ruleId: "sensitive.\(Self.normalized(rule.id))",
                    displayName: rule.displayName
                )
            }
        }

        return nil
    }

    private func matches(
        rule: SensitiveSceneRule,
        bundleId: String,
        windowTitle: String
    ) -> Bool {
        if !bundleId.isEmpty,
           rule.appBundleIds.contains(where: {
               Self.normalized($0) == bundleId
           }) {
            return true
        }

        if !windowTitle.isEmpty,
           rule.windowTitleKeywords.contains(where: {
               windowTitle.localizedCaseInsensitiveContains($0)
           }) {
            return true
        }

        if !windowTitle.isEmpty,
           rule.windowTitleRegexPatterns.contains(where: {
               windowTitle.range(of: $0, options: .regularExpression) != nil
           }) {
            return true
        }

        return false
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
