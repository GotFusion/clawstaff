import Foundation

public struct PreferenceProfileDirective: Codable, Equatable, Sendable {
    public let ruleId: String
    public let type: PreferenceSignalType
    public let scope: PreferenceSignalScopeReference
    public let statement: String
    public let hint: String?
    public let proposedAction: String?
    public let teacherConfirmed: Bool
    public let updatedAt: String

    public init(
        ruleId: String,
        type: PreferenceSignalType,
        scope: PreferenceSignalScopeReference,
        statement: String,
        hint: String? = nil,
        proposedAction: String? = nil,
        teacherConfirmed: Bool,
        updatedAt: String
    ) {
        self.ruleId = ruleId
        self.type = type
        self.scope = scope
        self.statement = statement
        self.hint = hint
        self.proposedAction = proposedAction
        self.teacherConfirmed = teacherConfirmed
        self.updatedAt = updatedAt
    }

    public init(rule: PreferenceRule) {
        self.init(
            ruleId: rule.ruleId,
            type: rule.type,
            scope: rule.scope,
            statement: rule.statement,
            hint: rule.hint,
            proposedAction: rule.proposedAction,
            teacherConfirmed: rule.teacherConfirmed,
            updatedAt: rule.updatedAt
        )
    }
}

public struct PreferenceProfile: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let profileVersion: String
    public let activeRuleIds: [String]
    public let assistPreferences: [PreferenceProfileDirective]
    public let skillPreferences: [PreferenceProfileDirective]
    public let repairPreferences: [PreferenceProfileDirective]
    public let reviewPreferences: [PreferenceProfileDirective]
    public let plannerPreferences: [PreferenceProfileDirective]
    public let generatedAt: String

    public init(
        schemaVersion: String = "openstaff.learning.preference-profile.v0",
        profileVersion: String,
        activeRuleIds: [String],
        assistPreferences: [PreferenceProfileDirective],
        skillPreferences: [PreferenceProfileDirective],
        repairPreferences: [PreferenceProfileDirective],
        reviewPreferences: [PreferenceProfileDirective],
        plannerPreferences: [PreferenceProfileDirective],
        generatedAt: String
    ) {
        self.schemaVersion = schemaVersion
        self.profileVersion = profileVersion
        self.activeRuleIds = Array(Set(activeRuleIds)).sorted()
        self.assistPreferences = assistPreferences
        self.skillPreferences = skillPreferences
        self.repairPreferences = repairPreferences
        self.reviewPreferences = reviewPreferences
        self.plannerPreferences = plannerPreferences
        self.generatedAt = generatedAt
    }

    public var totalDirectiveCount: Int {
        assistPreferences.count
            + skillPreferences.count
            + repairPreferences.count
            + reviewPreferences.count
            + plannerPreferences.count
    }
}

public struct PreferenceProfileSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let profileVersion: String
    public let profile: PreferenceProfile
    public let sourceRuleIds: [String]
    public let createdAt: String
    public let previousProfileVersion: String?
    public let note: String?

    public init(
        schemaVersion: String = "openstaff.learning.preference-profile-snapshot.v0",
        profile: PreferenceProfile,
        sourceRuleIds: [String],
        createdAt: String,
        previousProfileVersion: String? = nil,
        note: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.profileVersion = profile.profileVersion
        self.profile = profile
        self.sourceRuleIds = Array(Set(sourceRuleIds)).sorted()
        self.createdAt = createdAt
        self.previousProfileVersion = previousProfileVersion
        self.note = note
    }
}
