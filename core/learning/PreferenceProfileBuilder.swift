import Foundation

public enum PreferenceProfileModule: String, Codable, CaseIterable, Sendable {
    case assist
    case skill
    case repair
    case review
    case planner
}

public struct PreferenceProfileModuleSummary: Codable, Equatable, Sendable {
    public let module: PreferenceProfileModule
    public let directiveCount: Int
    public let ruleIds: [String]

    public init(
        module: PreferenceProfileModule,
        directiveCount: Int,
        ruleIds: [String]
    ) {
        self.module = module
        self.directiveCount = directiveCount
        self.ruleIds = Array(Set(ruleIds)).sorted()
    }
}

public struct PreferenceProfileBuildResult: Equatable, Sendable {
    public let profile: PreferenceProfile
    public let snapshot: PreferenceProfileSnapshot
    public let moduleSummaries: [PreferenceProfileModuleSummary]

    public init(
        profile: PreferenceProfile,
        snapshot: PreferenceProfileSnapshot,
        moduleSummaries: [PreferenceProfileModuleSummary]
    ) {
        self.profile = profile
        self.snapshot = snapshot
        self.moduleSummaries = moduleSummaries
    }
}

public struct PreferenceProfileBuildConfiguration: Equatable, Sendable {
    public init() {}

    public static let v0Default = Self()

    public func modules(for rule: PreferenceRule) -> [PreferenceProfileModule] {
        PreferenceProfileModule.allCases.filter { includes(rule, in: $0) }
    }

    public func includes(
        _ rule: PreferenceRule,
        in module: PreferenceProfileModule
    ) -> Bool {
        switch (rule.type, module) {
        case (.outcome, .review):
            return true
        case (.procedure, .assist), (.procedure, .skill), (.procedure, .review), (.procedure, .planner):
            return true
        case (.locator, .skill), (.locator, .repair), (.locator, .review):
            return true
        case (.style, .assist), (.style, .skill), (.style, .review):
            return true
        case (.risk, .assist), (.risk, .skill), (.risk, .review), (.risk, .planner):
            return true
        case (.repair, .repair), (.repair, .review), (.repair, .planner):
            return true
        default:
            return false
        }
    }
}

public struct PreferenceProfileBuilder: Sendable {
    public let configuration: PreferenceProfileBuildConfiguration
    public let conflictResolver: PreferenceConflictResolver

    public init(
        configuration: PreferenceProfileBuildConfiguration = .v0Default,
        conflictResolver: PreferenceConflictResolver = .v0Default
    ) {
        self.configuration = configuration
        self.conflictResolver = conflictResolver
    }

    public func build(
        from rules: [PreferenceRule],
        profileVersion: String,
        generatedAt: String,
        previousProfileVersion: String? = nil,
        note: String? = nil
    ) -> PreferenceProfileBuildResult {
        let orderedActiveRules = activeRules(from: rules)
        let assistPreferences = directives(for: .assist, from: orderedActiveRules)
        let skillPreferences = directives(for: .skill, from: orderedActiveRules)
        let repairPreferences = directives(for: .repair, from: orderedActiveRules)
        let reviewPreferences = directives(for: .review, from: orderedActiveRules)
        let plannerPreferences = directives(for: .planner, from: orderedActiveRules)

        let profile = PreferenceProfile(
            profileVersion: profileVersion,
            activeRuleIds: orderedActiveRules.map(\.ruleId),
            assistPreferences: assistPreferences,
            skillPreferences: skillPreferences,
            repairPreferences: repairPreferences,
            reviewPreferences: reviewPreferences,
            plannerPreferences: plannerPreferences,
            generatedAt: generatedAt
        )

        let snapshot = PreferenceProfileSnapshot(
            profile: profile,
            sourceRuleIds: profile.activeRuleIds,
            createdAt: generatedAt,
            previousProfileVersion: previousProfileVersion,
            note: note
        )

        return PreferenceProfileBuildResult(
            profile: profile,
            snapshot: snapshot,
            moduleSummaries: summaries(for: profile)
        )
    }

    public func rebuild(
        using store: PreferenceMemoryStore,
        profileVersion: String? = nil,
        generatedAt: String,
        note: String? = nil
    ) throws -> PreferenceProfileBuildResult {
        let rules = try store.loadRules()
        let previousSnapshot = try store.loadLatestProfileSnapshot()

        return build(
            from: rules,
            profileVersion: profileVersion ?? Self.derivedProfileVersion(generatedAt: generatedAt),
            generatedAt: generatedAt,
            previousProfileVersion: previousSnapshot?.profileVersion,
            note: note
        )
    }

    @discardableResult
    public func rebuildAndStore(
        using store: PreferenceMemoryStore,
        actor: String = "system",
        profileVersion: String? = nil,
        generatedAt: String,
        note: String? = nil
    ) throws -> PreferenceProfileBuildResult {
        let result = try rebuild(
            using: store,
            profileVersion: profileVersion,
            generatedAt: generatedAt,
            note: note
        )
        try store.storeProfileSnapshot(
            result.snapshot,
            actor: actor,
            note: note
        )
        return result
    }

    public func summaries(for profile: PreferenceProfile) -> [PreferenceProfileModuleSummary] {
        PreferenceProfileModule.allCases.map { module in
            let directives = profile.directives(for: module)
            return PreferenceProfileModuleSummary(
                module: module,
                directiveCount: directives.count,
                ruleIds: directives.map(\.ruleId)
            )
        }
    }

    public static func derivedProfileVersion(generatedAt: String) -> String {
        let token = sanitizedToken(generatedAt.lowercased())
        let suffix = UUID().uuidString.lowercased().prefix(8)
        return "profile-\(token)-\(suffix)"
    }

    private func directives(
        for module: PreferenceProfileModule,
        from rules: [PreferenceRule]
    ) -> [PreferenceProfileDirective] {
        rules
            .filter { configuration.includes($0, in: module) }
            .map(PreferenceProfileDirective.init(rule:))
    }

    private func activeRules(from rules: [PreferenceRule]) -> [PreferenceRule] {
        let orderedRules = rules.sorted(by: conflictResolver.sortsBefore)
        var seenRuleIds = Set<String>()
        var collected: [PreferenceRule] = []

        for rule in orderedRules where rule.isActive {
            guard seenRuleIds.insert(rule.ruleId).inserted else {
                continue
            }
            collected.append(rule)
        }

        return collected
    }

    private static func sanitizedToken(_ raw: String) -> String {
        let pieces = raw.split { !$0.isLetter && !$0.isNumber }
        let token = pieces.joined(separator: "-")
        return token.isEmpty ? "profile" : token
    }
}

public extension PreferenceProfile {
    func directives(for module: PreferenceProfileModule) -> [PreferenceProfileDirective] {
        switch module {
        case .assist:
            return assistPreferences
        case .skill:
            return skillPreferences
        case .repair:
            return repairPreferences
        case .review:
            return reviewPreferences
        case .planner:
            return plannerPreferences
        }
    }
}
