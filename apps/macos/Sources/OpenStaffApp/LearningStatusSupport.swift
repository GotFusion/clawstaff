import Foundation

protocol LearningContextSnapshotProviding {
    func snapshot(includeWindowContext: Bool) -> ContextSnapshot
}

struct SystemLearningContextSnapshotProvider: LearningContextSnapshotProviding {
    private let resolver: CaptureSemanticContextResolver

    init(resolver: CaptureSemanticContextResolver = CaptureSemanticContextResolver()) {
        self.resolver = resolver
    }

    func snapshot(includeWindowContext: Bool) -> ContextSnapshot {
        resolver.snapshot(
            pointer: nil,
            action: nil,
            includeWindowContext: includeWindowContext
        )
    }
}

protocol LearningLastSuccessfulWriteProviding {
    func latestSuccessfulWriteAt(rawEventsRootDirectory: URL) -> Date?
}

struct RawEventLastSuccessfulWriteProvider: LearningLastSuccessfulWriteProviding {
    func latestSuccessfulWriteAt(rawEventsRootDirectory: URL) -> Date? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rawEventsRootDirectory.path) else {
            return nil
        }

        guard let enumerator = fileManager.enumerator(
            at: rawEventsRootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var latestDate: Date?
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            ),
            values.isRegularFile == true,
            let modifiedAt = values.contentModificationDate else {
                continue
            }

            if let currentLatest = latestDate {
                if modifiedAt > currentLatest {
                    latestDate = modifiedAt
                }
            } else {
                latestDate = modifiedAt
            }
        }

        return latestDate
    }
}

struct LearningAppExclusionPolicy {
    private let excludedBundleIds: Set<String>
    private let excludedAppNames: Set<String>

    init(
        excludedBundleIds: Set<String> = [],
        excludedAppNames: Set<String> = []
    ) {
        self.excludedBundleIds = Set(excludedBundleIds.map(Self.normalized))
        self.excludedAppNames = Set(excludedAppNames.map(Self.normalized))
    }

    static func `default`(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LearningAppExclusionPolicy {
        let configuredBundleIds = environment["OPENSTAFF_LEARNING_EXCLUDED_BUNDLE_IDS"]?
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        return LearningAppExclusionPolicy(
            excludedBundleIds: Set(configuredBundleIds),
            excludedAppNames: ["OpenStaff"]
        )
    }

    func match(for app: LearningSurfaceAppContext) -> LearningStatusRuleMatch? {
        let normalizedBundleId = Self.normalized(app.appBundleId)
        let normalizedAppName = Self.normalized(app.appName)

        if normalizedBundleId.contains("openstaff") || normalizedAppName == "openstaff" {
            return LearningStatusRuleMatch(
                ruleId: "self.openstaff-ui",
                displayName: "OpenStaff 自身界面"
            )
        }

        if excludedBundleIds.contains(normalizedBundleId) {
            return LearningStatusRuleMatch(
                ruleId: "bundle.\(normalizedBundleId)",
                displayName: app.appName
            )
        }

        if excludedAppNames.contains(normalizedAppName) {
            return LearningStatusRuleMatch(
                ruleId: "app.\(normalizedAppName)",
                displayName: app.appName
            )
        }

        return nil
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct LearningSensitiveScenePolicy {
    let rules: [SensitiveWindowRule]

    init(rules: [SensitiveWindowRule] = SafetyPolicyRules.defaultSensitiveWindows) {
        self.rules = rules
    }

    func match(for app: LearningSurfaceAppContext) -> LearningStatusRuleMatch? {
        let bundleId = app.appBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let windowTitle = app.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        for rule in rules {
            if matches(rule: rule, bundleId: bundleId, windowTitle: windowTitle) {
                return LearningStatusRuleMatch(
                    ruleId: "sensitive.\(rule.tag)",
                    displayName: displayName(for: rule)
                )
            }
        }

        return nil
    }

    private func matches(
        rule: SensitiveWindowRule,
        bundleId: String,
        windowTitle: String
    ) -> Bool {
        if !bundleId.isEmpty,
           rule.appBundleIds.contains(where: {
               $0.caseInsensitiveCompare(bundleId) == .orderedSame
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

    private func displayName(for rule: SensitiveWindowRule) -> String {
        switch rule.tag {
        case "payment":
            return "支付 / 付款"
        case "system_settings":
            return "系统设置 / 隐私授权"
        case "password_manager":
            return "密码 / 钥匙串"
        case "privacy_permission_popup":
            return "隐私权限弹窗"
        default:
            return rule.tag
        }
    }
}

extension LearningSurfaceAppContext {
    init(snapshot: ContextSnapshot) {
        self.init(
            appName: snapshot.appName,
            appBundleId: snapshot.appBundleId,
            windowTitle: snapshot.windowTitle
        )
    }
}

@MainActor
final class DashboardLearningStatusRefreshTimerTarget: NSObject {
    weak var owner: OpenStaffDashboardViewModel?

    init(owner: OpenStaffDashboardViewModel) {
        self.owner = owner
    }

    @objc
    func handleTick(_ timer: Timer) {
        owner?.refreshLearningStatusSurface()
    }
}
