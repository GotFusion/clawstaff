import Foundation

public enum SkillRepairActionType: String, Codable, Equatable, Sendable {
    case relocalize
    case reteachCurrentStep
    case updateSkillLocator
}
