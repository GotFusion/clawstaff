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
    private let excludedWindowTitleRules: [LearningWindowTitleExclusionRule]

    init(
        excludedBundleIds: Set<String> = [],
        excludedAppNames: Set<String> = [],
        excludedWindowTitleRules: [LearningWindowTitleExclusionRule] = []
    ) {
        self.excludedBundleIds = Set(excludedBundleIds.map(Self.normalized))
        self.excludedAppNames = Set(excludedAppNames.map(Self.normalized))
        self.excludedWindowTitleRules = excludedWindowTitleRules.map { $0.normalized() }
    }

    static func `default`(
        settings: LearningPrivacyConfiguration = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LearningAppExclusionPolicy {
        let configuredBundleIds = environment["OPENSTAFF_LEARNING_EXCLUDED_BUNDLE_IDS"]?
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        let configuredAppBundleIds = settings.excludedApps
            .map(\.bundleId)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let configuredAppNames = settings.excludedApps
            .map(\.appName)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return LearningAppExclusionPolicy(
            excludedBundleIds: Set(configuredBundleIds + configuredAppBundleIds),
            excludedAppNames: Set(configuredAppNames + ["OpenStaff"]),
            excludedWindowTitleRules: settings.excludedWindowTitleRules
        )
    }

    func match(for app: LearningSurfaceAppContext) -> LearningStatusRuleMatch? {
        let normalizedBundleId = Self.normalized(app.appBundleId)
        let normalizedAppName = Self.normalized(app.appName)
        let windowTitle = app.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

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

        if !windowTitle.isEmpty {
            for rule in excludedWindowTitleRules where matches(rule: rule, windowTitle: windowTitle) {
                return LearningStatusRuleMatch(
                    ruleId: rule.id,
                    displayName: rule.resolvedDisplayName
                )
            }
        }

        return nil
    }

    private func matches(
        rule: LearningWindowTitleExclusionRule,
        windowTitle: String
    ) -> Bool {
        let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            return false
        }

        switch rule.matchType {
        case .contains:
            return windowTitle.localizedCaseInsensitiveContains(pattern)
        case .regex:
            return windowTitle.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
