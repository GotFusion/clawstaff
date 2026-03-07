import Foundation

// MARK: - Task Chunk (Session -> Task)

public struct TaskChunk: Codable, Equatable {
    public let schemaVersion: String
    public let taskId: String
    public let sessionId: String
    public let startTimestamp: String
    public let endTimestamp: String
    public let eventIds: [String]
    public let eventCount: Int
    public let primaryContext: ContextSnapshot
    public let boundaryReason: TaskBoundaryReason
    public let slicerVersion: String

    public init(
        schemaVersion: String = "knowledge.task-chunk.v0",
        taskId: String,
        sessionId: String,
        startTimestamp: String,
        endTimestamp: String,
        eventIds: [String],
        eventCount: Int,
        primaryContext: ContextSnapshot,
        boundaryReason: TaskBoundaryReason,
        slicerVersion: String = "rule-v0"
    ) {
        self.schemaVersion = schemaVersion
        self.taskId = taskId
        self.sessionId = sessionId
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.eventIds = eventIds
        self.eventCount = eventCount
        self.primaryContext = primaryContext
        self.boundaryReason = boundaryReason
        self.slicerVersion = slicerVersion
    }
}

public enum TaskBoundaryReason: String, Codable {
    case idleGap
    case contextSwitch
    case sessionEnd
}

public struct TaskSlicingPolicy: Codable, Equatable {
    public let idleGapSeconds: TimeInterval
    public let splitOnContextSwitch: Bool

    public init(
        idleGapSeconds: TimeInterval = 20,
        splitOnContextSwitch: Bool = true
    ) {
        self.idleGapSeconds = idleGapSeconds
        self.splitOnContextSwitch = splitOnContextSwitch
    }
}
