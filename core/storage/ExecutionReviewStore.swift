import Foundation

struct ExecutionLogSummary: Identifiable {
    let id: String
    let mode: OpenStaffMode
    let timestamp: Date
    let traceId: String?
    let sessionId: String
    let taskId: String?
    let status: String
    let message: String
    let component: String?
    let errorCode: String?
    let planId: String?
    let skillId: String?
    let planStepId: String?
    let skillName: String?
    let skillDirectoryPath: String?
    let sourceKnowledgeItemId: String?
    let sourceStepId: String?
    let stepId: String?
    let actionType: String?
    let exitCode: Int32?
    let sourceFilePath: String
    let lineNumber: Int
}

struct TeacherFeedbackSummary {
    let feedbackId: String
    let timestamp: Date
    let decision: TeacherFeedbackDecision
    let note: String?
}

struct ExecutionReviewSnapshot {
    let logs: [ExecutionLogSummary]
    let logById: [String: ExecutionLogSummary]
    let latestFeedbackByLogId: [String: TeacherFeedbackSummary]

    static let empty = ExecutionReviewSnapshot(logs: [], logById: [:], latestFeedbackByLogId: [:])
}

struct TeacherFeedbackWriteEntry: Codable {
    let schemaVersion: String
    let feedbackId: String
    let timestamp: String
    let reviewerRole: String
    let decision: TeacherFeedbackDecision
    let teacherReview: TeacherReviewEvidence
    let note: String?
    let sessionId: String
    let taskId: String?
    let logEntryId: String
    let logStatus: String
    let logMessage: String
    let component: String?
    let repairActionType: String?
    let repairStepIds: [String]?
    let skillName: String?
    let skillDirectoryPath: String?

    init(
        feedbackId: String,
        timestamp: String,
        decision: TeacherFeedbackDecision,
        note: String?,
        sessionId: String,
        taskId: String?,
        logEntryId: String,
        logStatus: String,
        logMessage: String,
        component: String?,
        repairActionType: String? = nil,
        repairStepIds: [String]? = nil,
        skillName: String? = nil,
        skillDirectoryPath: String? = nil
    ) {
        self.schemaVersion = "teacher.feedback.v2"
        self.feedbackId = feedbackId
        self.timestamp = timestamp
        self.reviewerRole = "teacher"
        self.decision = decision
        self.teacherReview = decision.makeTeacherReviewEvidence(
            note: note,
            repairActionType: repairActionType
        )
        self.note = note
        self.sessionId = sessionId
        self.taskId = taskId
        self.logEntryId = logEntryId
        self.logStatus = logStatus
        self.logMessage = logMessage
        self.component = component
        self.repairActionType = repairActionType
        self.repairStepIds = repairStepIds
        self.skillName = skillName
        self.skillDirectoryPath = skillDirectoryPath
    }
}

struct ExecutionReviewSkillRoot {
    let scopeId: String
    let directory: URL
}

struct ExecutionReviewColumnItem {
    let title: String
    let detail: String
}

enum ExecutionReviewResultStatus {
    case succeeded
    case failed
    case blocked
    case unknown

    var displayName: String {
        switch self {
        case .succeeded:
            return "执行成功"
        case .failed:
            return "执行失败"
        case .blocked:
            return "执行阻断"
        case .unknown:
            return "暂无结果"
        }
    }
}

struct ExecutionReviewComparisonRow: Identifiable {
    let id: String
    let order: Int
    let teacherStep: ExecutionReviewColumnItem
    let skillStep: ExecutionReviewColumnItem
    let actualResult: ExecutionReviewColumnItem
    let resultStatus: ExecutionReviewResultStatus
    let knowledgeStepId: String?
    let skillStepId: String?
    let preferredRepairActionType: SkillRepairActionType?
}

struct ExecutionReviewRepairAction {
    let type: SkillRepairActionType
    let title: String
    let reason: String
    let affectedStepIds: [String]
}

struct ExecutionReviewSuggestionRuleHit {
    let ruleId: String
    let signalType: PreferenceSignalType
    let scopeLevel: PreferenceSignalScope
    let matchScore: Double
    let priorityDelta: Double
    let explanation: String
}

struct ExecutionReviewSuggestion: Identifiable {
    let id: String
    let action: TeacherQuickFeedbackAction
    let summary: String
    let suggestedNote: String?
    let appliedRuleIds: [String]
    let priority: Double
}

struct ExecutionReviewSuggestionDecision {
    let profileVersion: String
    let appliedRuleIds: [String]
    let summary: String
}

struct ExecutionReviewDetail {
    let logId: String
    let goal: String?
    let knowledgeItemId: String?
    let knowledgeSummary: String?
    let skillId: String?
    let skillName: String?
    let skillDirectoryPath: String?
    let currentRepairVersion: Int?
    let comparisonRows: [ExecutionReviewComparisonRow]
    let locatorRepairAction: ExecutionReviewRepairAction?
    let reteachAction: ExecutionReviewRepairAction?
    let reviewSuggestions: [ExecutionReviewSuggestion]
    let reviewPreferenceDecision: ExecutionReviewSuggestionDecision?

    var hasActionableRepair: Bool {
        locatorRepairAction != nil || reteachAction != nil
    }
}

struct ExecutionReviewStore {
    private let logsRootDirectory: URL
    private let feedbackRootDirectory: URL
    private let reportsRootDirectory: URL
    private let knowledgeRootDirectory: URL
    private let preferencesRootDirectory: URL?
    private let skillRoots: [ExecutionReviewSkillRoot]
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        logsRootDirectory: URL,
        feedbackRootDirectory: URL,
        reportsRootDirectory: URL,
        knowledgeRootDirectory: URL,
        preferencesRootDirectory: URL? = nil,
        skillRoots: [ExecutionReviewSkillRoot],
        fileManager: FileManager = .default
    ) {
        self.logsRootDirectory = logsRootDirectory
        self.feedbackRootDirectory = feedbackRootDirectory
        self.reportsRootDirectory = reportsRootDirectory
        self.knowledgeRootDirectory = knowledgeRootDirectory
        self.preferencesRootDirectory = preferencesRootDirectory
        self.skillRoots = skillRoots
        self.fileManager = fileManager
        self.decoder = JSONDecoder()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    func loadExecutionSnapshot(limit: Int) -> ExecutionReviewSnapshot {
        let logs = loadLogs(limit: limit)
        var logById: [String: ExecutionLogSummary] = [:]
        logById.reserveCapacity(logs.count)
        for log in logs {
            logById[log.id] = log
        }

        let latestFeedbackByLogId = loadLatestFeedbackByLogId()
        return ExecutionReviewSnapshot(
            logs: logs,
            logById: logById,
            latestFeedbackByLogId: latestFeedbackByLogId
        )
    }

    func loadDetail(for log: ExecutionLogSummary) -> ExecutionReviewDetail {
        let relatedLogs = loadRelatedLogs(for: log)
        let report = loadMatchingStudentReport(for: log)
        let skill = resolveSkill(for: log, relatedLogs: relatedLogs, report: report)
        let knowledgeItem = resolveKnowledgeItem(for: log, report: report, skill: skill)
        let comparisonRows = buildComparisonRows(
            selectedLog: log,
            relatedLogs: relatedLogs,
            report: report,
            knowledgeItem: knowledgeItem,
            skill: skill
        )

        let failedRows = preferredRepairRows(for: log, rows: comparisonRows)
        let locatorRepairAction = buildLocatorRepairAction(skill: skill, rows: failedRows)
        let reteachAction = buildReteachAction(skill: skill, rows: failedRows)
        let reviewSuggestionResult = buildReviewSuggestionResult(
            selectedLog: log,
            comparisonRows: comparisonRows,
            knowledgeItem: knowledgeItem,
            skill: skill,
            locatorRepairAction: locatorRepairAction,
            reteachAction: reteachAction
        )

        return ExecutionReviewDetail(
            logId: log.id,
            goal: knowledgeItem?.goal ?? report?.goal,
            knowledgeItemId: knowledgeItem?.knowledgeItemId ?? report?.plan.selectedKnowledgeItemId ?? skill?.payload.knowledgeItemId,
            knowledgeSummary: knowledgeItem?.summary ?? report?.summary,
            skillId: skill?.skillId,
            skillName: skill?.payload.skillName,
            skillDirectoryPath: skill?.directory.path,
            currentRepairVersion: skill?.payload.provenance?.skillBuild?.repairVersion,
            comparisonRows: comparisonRows,
            locatorRepairAction: locatorRepairAction,
            reteachAction: reteachAction,
            reviewSuggestions: reviewSuggestionResult.suggestions,
            reviewPreferenceDecision: reviewSuggestionResult.decision
        )
    }

    func appendTeacherFeedback(_ entry: TeacherFeedbackWriteEntry) throws {
        let directory = feedbackRootDirectory
            .appendingPathComponent(Self.dateKey(from: entry.timestamp), isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let safeTaskId = entry.taskId ?? "no-task"
        let fileURL = directory.appendingPathComponent("\(entry.sessionId)-\(safeTaskId)-teacher-feedback.jsonl")
        var payload = try encoder.encode(entry)
        payload.append(0x0A)

        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
            try handle.close()
        } else {
            try payload.write(to: fileURL, options: .atomic)
        }
    }

    private func loadLogs(limit: Int) -> [ExecutionLogSummary] {
        let logFiles = listFiles(withExtension: "log", under: logsRootDirectory)
        guard !logFiles.isEmpty else {
            return []
        }

        var logs: [ExecutionLogSummary] = []
        logs.reserveCapacity(256)

        for fileURL in logFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            let fileName = fileURL.lastPathComponent.lowercased()
            let defaultMode = inferMode(fromFileName: fileName)

            for (index, line) in content.split(whereSeparator: \.isNewline).enumerated() {
                guard let data = line.data(using: .utf8),
                      let record = try? decoder.decode(ExecutionLogRecord.self, from: data),
                      let timestamp = ExecutionReviewDateSupport.date(from: record.timestamp) else {
                    continue
                }

                let lineNumber = index + 1
                let logId = "\(fileURL.path)#L\(lineNumber)"
                logs.append(
                    ExecutionLogSummary(
                        id: logId,
                        mode: inferMode(component: record.component) ?? defaultMode,
                        timestamp: timestamp,
                        traceId: record.traceId,
                        sessionId: record.sessionId,
                        taskId: record.taskId,
                        status: record.status,
                        message: record.message,
                        component: record.component,
                        errorCode: record.errorCode,
                        planId: record.planId,
                        skillId: record.skillId,
                        planStepId: record.planStepId,
                        skillName: record.skillName,
                        skillDirectoryPath: record.skillDirectoryPath,
                        sourceKnowledgeItemId: record.sourceKnowledgeItemId,
                        sourceStepId: record.sourceStepId,
                        stepId: record.stepId,
                        actionType: record.actionType,
                        exitCode: record.exitCode,
                        sourceFilePath: fileURL.path,
                        lineNumber: lineNumber
                    )
                )
            }
        }

        let sorted = logs.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id < rhs.id
            }
            return lhs.timestamp > rhs.timestamp
        }

        if sorted.count <= limit {
            return sorted
        }
        return Array(sorted.prefix(limit))
    }

    private func loadLatestFeedbackByLogId() -> [String: TeacherFeedbackSummary] {
        let feedbackFiles = listFiles(withExtension: "jsonl", under: feedbackRootDirectory)
        guard !feedbackFiles.isEmpty else {
            return [:]
        }

        var latestByLogId: [String: TeacherFeedbackSummary] = [:]
        latestByLogId.reserveCapacity(64)

        for fileURL in feedbackFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            for line in content.split(whereSeparator: \.isNewline) {
                guard let data = line.data(using: .utf8),
                      let record = try? decoder.decode(TeacherFeedbackReadRecord.self, from: data),
                      let timestamp = ExecutionReviewDateSupport.date(from: record.timestamp) else {
                    continue
                }

                let summary = TeacherFeedbackSummary(
                    feedbackId: record.feedbackId,
                    timestamp: timestamp,
                    decision: record.decision,
                    note: record.note
                )

                if let existing = latestByLogId[record.logEntryId] {
                    if summary.timestamp >= existing.timestamp {
                        latestByLogId[record.logEntryId] = summary
                    }
                } else {
                    latestByLogId[record.logEntryId] = summary
                }
            }
        }

        return latestByLogId
    }

    private func loadRelatedLogs(for log: ExecutionLogSummary) -> [ExecutionLogSummary] {
        guard let content = try? String(contentsOfFile: log.sourceFilePath, encoding: .utf8) else {
            return [log]
        }

        let defaultMode = inferMode(fromFileName: URL(fileURLWithPath: log.sourceFilePath).lastPathComponent.lowercased())
        let parsed: [ExecutionLogSummary] = content
            .split(whereSeparator: \.isNewline)
            .enumerated()
            .compactMap { index, line in
                guard let data = line.data(using: .utf8),
                      let record = try? decoder.decode(ExecutionLogRecord.self, from: data),
                      let timestamp = ExecutionReviewDateSupport.date(from: record.timestamp) else {
                    return nil
                }

                return ExecutionLogSummary(
                    id: "\(log.sourceFilePath)#L\(index + 1)",
                    mode: inferMode(component: record.component) ?? defaultMode,
                    timestamp: timestamp,
                    traceId: record.traceId,
                    sessionId: record.sessionId,
                    taskId: record.taskId,
                    status: record.status,
                    message: record.message,
                    component: record.component,
                    errorCode: record.errorCode,
                    planId: record.planId,
                    skillId: record.skillId,
                    planStepId: record.planStepId,
                    skillName: record.skillName,
                    skillDirectoryPath: record.skillDirectoryPath,
                    sourceKnowledgeItemId: record.sourceKnowledgeItemId,
                    sourceStepId: record.sourceStepId,
                    stepId: record.stepId,
                    actionType: record.actionType,
                    exitCode: record.exitCode,
                    sourceFilePath: log.sourceFilePath,
                    lineNumber: index + 1
                )
            }

        let traceId = log.traceId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = parsed.filter { item in
            if let traceId, !traceId.isEmpty {
                return item.traceId == traceId
            }
            return item.sessionId == log.sessionId && item.taskId == log.taskId
        }

        if filtered.isEmpty {
            return [log]
        }

        return filtered.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.lineNumber < rhs.lineNumber
            }
            return lhs.timestamp < rhs.timestamp
        }
    }

    private func loadMatchingStudentReport(for log: ExecutionLogSummary) -> StudentReviewReport? {
        let reportFiles = listFiles(withExtension: "json", under: reportsRootDirectory)
        guard !reportFiles.isEmpty else {
            return nil
        }

        var candidates: [(StudentReviewReport, Date)] = []
        candidates.reserveCapacity(8)

        for fileURL in reportFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  let report = try? decoder.decode(StudentReviewReport.self, from: data),
                  report.sessionId == log.sessionId else {
                continue
            }

            if let traceId = log.traceId, !traceId.isEmpty, report.traceId == traceId,
               let finishedAt = ExecutionReviewDateSupport.date(from: report.finishedAt) {
                candidates.append((report, finishedAt))
                continue
            }

            if report.taskId == log.taskId,
               let finishedAt = ExecutionReviewDateSupport.date(from: report.finishedAt) {
                candidates.append((report, finishedAt))
            }
        }

        return candidates
            .sorted { lhs, rhs in lhs.1 > rhs.1 }
            .first?
            .0
    }

    private func resolveSkill(
        for log: ExecutionLogSummary,
        relatedLogs: [ExecutionLogSummary],
        report: StudentReviewReport?
    ) -> ResolvedSkill? {
        let candidatePaths = ([log.skillDirectoryPath] + relatedLogs.map(\.skillDirectoryPath))
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

        for path in candidatePaths {
            if let skill = loadSkill(atDirectoryPath: path) {
                return skill
            }
        }

        let desiredKnowledgeItemId = log.sourceKnowledgeItemId
            ?? relatedLogs.compactMap(\.sourceKnowledgeItemId).first
            ?? report?.plan.selectedKnowledgeItemId
        let desiredSkillName = log.skillName
            ?? relatedLogs.compactMap(\.skillName).first
            ?? extractSkillName(from: relatedLogs)

        let candidates = loadAllSkills()
        guard !candidates.isEmpty else {
            return nil
        }

        let scored = candidates.map { candidate -> (ResolvedSkill, Int) in
            var score = 0

            if let desiredKnowledgeItemId, candidate.payload.knowledgeItemId == desiredKnowledgeItemId {
                score += 120
            }
            if candidate.payload.sessionId == log.sessionId {
                score += 60
            }
            if candidate.payload.taskId == log.taskId {
                score += 30
            }
            if let desiredSkillName, candidate.payload.skillName == desiredSkillName {
                score += 80
            }

            return (candidate, score)
        }
        .filter { $0.1 > 0 }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.payload.createdAt > rhs.0.payload.createdAt
            }
            return lhs.1 > rhs.1
        }

        return scored.first?.0
    }

    private func resolveKnowledgeItem(
        for log: ExecutionLogSummary,
        report: StudentReviewReport?,
        skill: ResolvedSkill?
    ) -> KnowledgeItem? {
        let knowledgeItemId = log.sourceKnowledgeItemId
            ?? report?.plan.selectedKnowledgeItemId
            ?? skill?.payload.knowledgeItemId

        if let knowledgeItemId, let item = loadKnowledgeItem(id: knowledgeItemId) {
            return item
        }

        let candidates = loadKnowledgeItems()
            .filter { item in
                item.sessionId == log.sessionId && item.taskId == log.taskId
            }
            .sorted { lhs, rhs in lhs.createdAt > rhs.createdAt }

        return candidates.first
    }

    private func buildComparisonRows(
        selectedLog: ExecutionLogSummary,
        relatedLogs: [ExecutionLogSummary],
        report: StudentReviewReport?,
        knowledgeItem: KnowledgeItem?,
        skill: ResolvedSkill?
    ) -> [ExecutionReviewComparisonRow] {
        if let skill {
            return buildSkillComparisonRows(
                selectedLog: selectedLog,
                relatedLogs: relatedLogs,
                knowledgeItem: knowledgeItem,
                skill: skill
            )
        }

        if let report {
            return buildPlanComparisonRows(report: report, knowledgeItem: knowledgeItem)
        }

        return [
            ExecutionReviewComparisonRow(
                id: selectedLog.id,
                order: 1,
                teacherStep: ExecutionReviewColumnItem(
                    title: "未关联老师原始步骤",
                    detail: "当前日志没有匹配到知识条目或步骤映射。"
                ),
                skillStep: ExecutionReviewColumnItem(
                    title: "未关联当前 skill",
                    detail: selectedLog.component ?? "无组件信息"
                ),
                actualResult: ExecutionReviewColumnItem(
                    title: resultStatus(from: selectedLog).displayName,
                    detail: selectedLog.message
                ),
                resultStatus: resultStatus(from: selectedLog),
                knowledgeStepId: nil,
                skillStepId: nil,
                preferredRepairActionType: nil
            )
        ]
    }

    private func buildSkillComparisonRows(
        selectedLog: ExecutionLogSummary,
        relatedLogs: [ExecutionLogSummary],
        knowledgeItem: KnowledgeItem?,
        skill: ResolvedSkill
    ) -> [ExecutionReviewComparisonRow] {
        let knowledgeStepsById = Dictionary(
            uniqueKeysWithValues: (knowledgeItem?.steps ?? []).map { ($0.stepId, $0) }
        )
        let stepMappings = Dictionary(
            uniqueKeysWithValues: (skill.payload.provenance?.stepMappings ?? []).map { ($0.skillStepId, $0) }
        )
        let logResults = buildSkillResultLookup(
            selectedLog: selectedLog,
            relatedLogs: relatedLogs,
            skill: skill
        )

        return skill.payload.mappedOutput.executionPlan.steps.enumerated().map { index, step in
            let mapping = stepMappings[step.stepId]
            let knowledgeStep = mapping.flatMap { mapping in
                mapping.knowledgeStepId.flatMap { knowledgeStepsById[$0] }
            } ?? knowledgeItem?.steps[safe: index]
            let result = logResults.bySkillStepId[step.stepId] ?? logResults.byOrder[index]

            let teacherTitle: String
            let teacherDetail: String
            if let knowledgeStep {
                teacherTitle = "老师步骤 \(index + 1) · \(knowledgeStep.stepId)"
                teacherDetail = knowledgeStep.instruction
            } else {
                teacherTitle = "老师步骤 \(index + 1)"
                teacherDetail = "当前 skill 未携带知识步骤映射。"
            }

            let skillDetail = [
                "\(step.actionType) · \(step.instruction)",
                "target: \(step.target)",
                locatorSummary(mapping: mapping)
            ]
            .joined(separator: "\n")

            return ExecutionReviewComparisonRow(
                id: "skill-row-\(step.stepId)",
                order: index + 1,
                teacherStep: ExecutionReviewColumnItem(title: teacherTitle, detail: teacherDetail),
                skillStep: ExecutionReviewColumnItem(
                    title: "Skill 步骤 \(index + 1) · \(step.stepId)",
                    detail: skillDetail
                ),
                actualResult: ExecutionReviewColumnItem(
                    title: result?.status.displayName ?? ExecutionReviewResultStatus.unknown.displayName,
                    detail: actualResultDetail(from: result, fallbackMessage: step.instruction)
                ),
                resultStatus: result?.status ?? .unknown,
                knowledgeStepId: knowledgeStep?.stepId ?? mapping?.knowledgeStepId,
                skillStepId: step.stepId,
                preferredRepairActionType: preferredLocatorRepairType(for: mapping)
            )
        }
    }

    private func buildPlanComparisonRows(
        report: StudentReviewReport,
        knowledgeItem: KnowledgeItem?
    ) -> [ExecutionReviewComparisonRow] {
        let knowledgeStepsById = Dictionary(
            uniqueKeysWithValues: (knowledgeItem?.steps ?? []).map { ($0.stepId, $0) }
        )
        let resultsByPlanStepId = Dictionary(
            uniqueKeysWithValues: report.stepResults.map { ($0.planStepId, $0) }
        )

        return report.plan.steps.enumerated().map { index, planStep in
            let knowledgeStep = knowledgeStepsById[planStep.sourceStepId] ?? knowledgeItem?.steps[safe: index]
            let result = resultsByPlanStepId[planStep.planStepId]

            return ExecutionReviewComparisonRow(
                id: "plan-row-\(planStep.planStepId)",
                order: index + 1,
                teacherStep: ExecutionReviewColumnItem(
                    title: "老师步骤 \(index + 1) · \(knowledgeStep?.stepId ?? planStep.sourceStepId)",
                    detail: knowledgeStep?.instruction ?? "未找到对应老师原始步骤。"
                ),
                skillStep: ExecutionReviewColumnItem(
                    title: "当前计划步骤 \(index + 1) · \(planStep.planStepId)",
                    detail: [
                        planStep.instruction,
                        "confidence: \(String(format: "%.2f", planStep.confidence))",
                        "skillId: \(planStep.skillId)"
                    ].joined(separator: "\n")
                ),
                actualResult: ExecutionReviewColumnItem(
                    title: resultStatus(from: result).displayName,
                    detail: result?.output ?? "暂无本次执行结果。"
                ),
                resultStatus: resultStatus(from: result),
                knowledgeStepId: knowledgeStep?.stepId ?? planStep.sourceStepId,
                skillStepId: nil,
                preferredRepairActionType: nil
            )
        }
    }

    private func buildSkillResultLookup(
        selectedLog: ExecutionLogSummary,
        relatedLogs: [ExecutionLogSummary],
        skill: ResolvedSkill
    ) -> SkillResultLookup {
        let candidateLogs = relatedLogs.filter { log in
            if let skillDirectoryPath = log.skillDirectoryPath,
               skillDirectoryPath == skill.directory.path {
                return true
            }
            if let skillName = log.skillName,
               skillName == skill.payload.skillName {
                return true
            }
            if log.component?.contains(".step") == true {
                return true
            }
            if log.component == "student.skill.single-run",
               log.planStepId != nil {
                return true
            }
            return false
        }

        var bySkillStepId: [String: ReviewExecutionResult] = [:]
        var byOrder: [Int: ReviewExecutionResult] = [:]
        let orderedStepLogs = candidateLogs
            .filter { $0.planStepId != nil || $0.stepId != nil || $0.sourceStepId != nil }
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.lineNumber < rhs.lineNumber
                }
                return lhs.timestamp < rhs.timestamp
            }

        for (index, log) in orderedStepLogs.enumerated() {
            let result = ReviewExecutionResult(
                status: resultStatus(from: log),
                output: log.message,
                errorCode: log.errorCode
            )
            if let stepId = log.stepId {
                bySkillStepId[stepId] = result
                continue
            }
            if let sourceStepId = log.sourceStepId {
                bySkillStepId[sourceStepId] = result
                continue
            }
            byOrder[index] = result
        }

        if bySkillStepId.isEmpty, byOrder.isEmpty {
            let result = ReviewExecutionResult(
                status: resultStatus(from: selectedLog),
                output: selectedLog.message,
                errorCode: selectedLog.errorCode
            )
            byOrder[0] = result
        }

        return SkillResultLookup(bySkillStepId: bySkillStepId, byOrder: byOrder)
    }

    private func preferredRepairRows(
        for selectedLog: ExecutionLogSummary,
        rows: [ExecutionReviewComparisonRow]
    ) -> [ExecutionReviewComparisonRow] {
        let actionable = rows.filter { row in
            row.resultStatus == .failed || row.resultStatus == .blocked
        }
        guard !actionable.isEmpty else {
            return []
        }

        if let selectedSkillStepId = selectedLog.stepId ?? selectedLog.sourceStepId,
           let exact = actionable.first(where: { $0.skillStepId == selectedSkillStepId }) {
            return [exact]
        }

        if let selectedPlanStepId = selectedLog.planStepId,
           let exact = actionable.first(where: { $0.id.hasSuffix(selectedPlanStepId) }) {
            return [exact]
        }

        return actionable
    }

    private func buildLocatorRepairAction(
        skill: ResolvedSkill?,
        rows: [ExecutionReviewComparisonRow]
    ) -> ExecutionReviewRepairAction? {
        guard skill != nil, !rows.isEmpty else {
            return nil
        }

        let affectedStepIds = rows.compactMap(\.skillStepId)
        guard !affectedStepIds.isEmpty else {
            return nil
        }

        let actionType: SkillRepairActionType = rows.contains(where: { $0.preferredRepairActionType == .relocalize })
            ? .relocalize
            : .updateSkillLocator

        return ExecutionReviewRepairAction(
            type: actionType,
            title: "修复 locator",
            reason: "老师在审阅台判定当前 skill 的定位信息已失效，需要修复受影响步骤的 locator。",
            affectedStepIds: affectedStepIds
        )
    }

    private func buildReteachAction(
        skill: ResolvedSkill?,
        rows: [ExecutionReviewComparisonRow]
    ) -> ExecutionReviewRepairAction? {
        guard skill != nil, !rows.isEmpty else {
            return nil
        }

        let affectedStepIds = rows.compactMap(\.skillStepId)
        guard !affectedStepIds.isEmpty else {
            return nil
        }

        return ExecutionReviewRepairAction(
            type: .reteachCurrentStep,
            title: "重新示教",
            reason: "老师在审阅台判定当前失败步骤应回到教学模式重新采集，以刷新 skill 步骤来源。",
            affectedStepIds: affectedStepIds
        )
    }

    private func buildReviewSuggestionResult(
        selectedLog: ExecutionLogSummary,
        comparisonRows: [ExecutionReviewComparisonRow],
        knowledgeItem: KnowledgeItem?,
        skill: ResolvedSkill?,
        locatorRepairAction: ExecutionReviewRepairAction?,
        reteachAction: ExecutionReviewRepairAction?
    ) -> ExecutionReviewSuggestionResult {
        let overallStatus = overallResultStatus(
            selectedLog: selectedLog,
            comparisonRows: comparisonRows
        )
        let context = ReviewSuggestionContext(
            selectedLog: selectedLog,
            comparisonRows: comparisonRows,
            knowledgeItem: knowledgeItem,
            skill: skill,
            locatorRepairAction: locatorRepairAction,
            reteachAction: reteachAction,
            overallStatus: overallStatus
        )
        let baseCandidates = buildBaseReviewSuggestionCandidates(
            context: context,
            locatorRepairAction: locatorRepairAction,
            reteachAction: reteachAction
        )

        guard !baseCandidates.isEmpty else {
            return ExecutionReviewSuggestionResult(suggestions: [], decision: nil)
        }

        guard let profile = loadLatestReviewPreferenceProfile(),
              !profile.reviewPreferences.isEmpty else {
            let suggestions = baseCandidates
                .sorted(by: baselineSuggestionSort)
                .compactMap { candidate in
                    buildReviewSuggestion(
                        from: candidate,
                        finalPriority: candidate.basePriority,
                        ruleHits: [],
                        copyStyleDirective: nil,
                        context: context
                    )
                }
            return ExecutionReviewSuggestionResult(suggestions: suggestions, decision: nil)
        }

        let copyStyleDirective = matchedReviewCopyStyleDirective(
            directives: profile.reviewPreferences,
            context: context
        )
        let rankedCandidates = baseCandidates.map { candidate in
            evaluateReviewSuggestionCandidate(
                candidate,
                directives: profile.reviewPreferences,
                context: context
            )
        }
        let sortedCandidates = rankedCandidates.sorted(by: rankedReviewSuggestionSort)
        let suggestions = sortedCandidates.compactMap { candidate in
            buildReviewSuggestion(
                from: candidate.baseline,
                finalPriority: candidate.finalPriority,
                ruleHits: candidate.ruleHits,
                copyStyleDirective: copyStyleDirective,
                context: context
            )
        }

        let appliedRuleIds = Array(
            Set(
                sortedCandidates.flatMap { candidate in
                    candidate.ruleHits.map(\.ruleId)
                }
                + (copyStyleDirective.map { [$0.ruleId] } ?? [])
            )
        ).sorted()

        let decision: ExecutionReviewSuggestionDecision?
        if let selected = sortedCandidates.first,
           !selected.ruleHits.isEmpty || copyStyleDirective != nil {
            decision = ExecutionReviewSuggestionDecision(
                profileVersion: profile.profileVersion,
                appliedRuleIds: appliedRuleIds,
                summary: buildReviewSuggestionDecisionSummary(
                    profileVersion: profile.profileVersion,
                    selected: selected,
                    copyStyleDirective: copyStyleDirective
                )
            )
        } else {
            decision = nil
        }

        return ExecutionReviewSuggestionResult(
            suggestions: suggestions,
            decision: decision
        )
    }

    private func buildBaseReviewSuggestionCandidates(
        context: ReviewSuggestionContext,
        locatorRepairAction: ExecutionReviewRepairAction?,
        reteachAction: ExecutionReviewRepairAction?
    ) -> [ExecutionReviewSuggestionBaseline] {
        var candidates: [ExecutionReviewSuggestionBaseline] = []

        let approvedPriority = context.overallStatus == .succeeded ? 0.9 : 0.06
        candidates.append(
            ExecutionReviewSuggestionBaseline(
                action: .approved,
                basePriority: approvedPriority,
                baseReason: "当前执行结果整体可接受，适合直接给出正向审阅。"
            )
        )

        let rejectedPriority: Double
        if context.hasBlocked {
            rejectedPriority = 0.58
        } else if context.hasFailure {
            rejectedPriority = 0.72
        } else {
            rejectedPriority = 0.18
        }
        candidates.append(
            ExecutionReviewSuggestionBaseline(
                action: .rejected,
                basePriority: rejectedPriority,
                baseReason: "当前日志存在未接受结果，至少需要明确驳回并补一句原因。"
            )
        )

        if locatorRepairAction != nil {
            let priority = context.likelyLocatorScore >= 0.55 ? 0.84 : 0.48
            candidates.append(
                ExecutionReviewSuggestionBaseline(
                    action: .fixLocator,
                    basePriority: priority,
                    baseReason: "失败更像 locator / anchor 漂移，适合先走“修 locator”。"
                )
            )
        }

        if reteachAction != nil {
            let priority = context.likelyLocatorScore >= 0.55 ? 0.36 : 0.58
            candidates.append(
                ExecutionReviewSuggestionBaseline(
                    action: .reteach,
                    basePriority: priority,
                    baseReason: "当前步骤本身可能已偏离老师原始做法，适合重新示教。"
                )
            )
        }

        let dangerPriority = context.hasBlocked ? 0.86 : max(0.12, context.riskSignalScore * 0.82)
        candidates.append(
            ExecutionReviewSuggestionBaseline(
                action: .tooDangerous,
                basePriority: dangerPriority,
                baseReason: "当前日志出现风险阻断或高风险信号，更适合标记为“太危险”。"
            )
        )

        let orderPriority = context.likelyOrderScore >= 0.45 ? 0.52 : max(0.08, context.likelyOrderScore * 0.5)
        candidates.append(
            ExecutionReviewSuggestionBaseline(
                action: .wrongOrder,
                basePriority: orderPriority,
                baseReason: "当前执行顺序与老师原始步骤可能存在偏移。"
            )
        )

        let stylePriority = context.likelyStyleScore >= 0.45 ? 0.46 : max(0.08, context.likelyStyleScore * 0.48)
        candidates.append(
            ExecutionReviewSuggestionBaseline(
                action: .wrongStyle,
                basePriority: stylePriority,
                baseReason: "当前操作方式与老师常用风格存在差异。"
            )
        )

        return candidates.filter { candidate in
            candidate.basePriority >= 0.16
        }
    }

    private func evaluateReviewSuggestionCandidate(
        _ candidate: ExecutionReviewSuggestionBaseline,
        directives: [PreferenceProfileDirective],
        context: ReviewSuggestionContext
    ) -> RankedExecutionReviewSuggestion {
        let ruleHits = directives.compactMap { directive in
            evaluateReviewDirective(
                directive,
                for: candidate.action,
                context: context
            )
        }
        let priorityDelta = ruleHits.reduce(0.0) { partial, hit in
            partial + hit.priorityDelta
        }

        return RankedExecutionReviewSuggestion(
            baseline: candidate,
            finalPriority: rounded(candidate.basePriority + priorityDelta),
            ruleHits: ruleHits.sorted(by: reviewSuggestionRuleHitSort)
        )
    }

    private func evaluateReviewDirective(
        _ directive: PreferenceProfileDirective,
        for action: TeacherQuickFeedbackAction,
        context: ReviewSuggestionContext
    ) -> ExecutionReviewSuggestionRuleHit? {
        let scopeScore = scopeMatchScore(for: directive.scope, context: context)
        guard scopeScore > 0 else {
            return nil
        }

        let interpretation = interpretedReviewPreference(for: directive, context: context)
        guard interpretation != .conciseCopy else {
            return nil
        }

        let affinity = interpretation.affinity(for: action, context: context)
        guard abs(affinity) >= 0.08 else {
            return nil
        }

        let teacherMultiplier = directive.teacherConfirmed ? 1.0 : 0.82
        let priorityDelta = rounded(scopeScore * affinity * 0.34 * teacherMultiplier)
        guard abs(priorityDelta) >= 0.01 else {
            return nil
        }

        return ExecutionReviewSuggestionRuleHit(
            ruleId: directive.ruleId,
            signalType: directive.type,
            scopeLevel: directive.scope.level,
            matchScore: rounded(scopeScore),
            priorityDelta: priorityDelta,
            explanation: buildReviewRuleHitExplanation(
                directive: directive,
                interpretation: interpretation,
                action: action,
                priorityDelta: priorityDelta
            )
        )
    }

    private func buildReviewSuggestion(
        from candidate: ExecutionReviewSuggestionBaseline,
        finalPriority: Double,
        ruleHits: [ExecutionReviewSuggestionRuleHit],
        copyStyleDirective: PreferenceProfileDirective?,
        context: ReviewSuggestionContext
    ) -> ExecutionReviewSuggestion? {
        let appliedRuleIds = Array(
            Set(
                ruleHits.map(\.ruleId)
                + (copyStyleDirective.map { [$0.ruleId] } ?? [])
            )
        ).sorted()

        var summary = candidate.baseReason
        if let topHit = ruleHits.first {
            summary = "\(candidate.baseReason) 命中规则 \(appliedRuleIds.joined(separator: "、"))，\(topHit.explanation)"
        }
        if let copyStyleDirective {
            summary += " 备注建议同时遵循 \(copyStyleDirective.ruleId) 的结论前置风格。"
        }

        let suggestedNote = buildSuggestedReviewNote(
            action: candidate.action,
            context: context,
            prefersConciseCopy: copyStyleDirective != nil
        )

        return ExecutionReviewSuggestion(
            id: candidate.action.rawValue,
            action: candidate.action,
            summary: summary,
            suggestedNote: suggestedNote,
            appliedRuleIds: appliedRuleIds,
            priority: finalPriority
        )
    }

    private func buildReviewSuggestionDecisionSummary(
        profileVersion: String,
        selected: RankedExecutionReviewSuggestion,
        copyStyleDirective: PreferenceProfileDirective?
    ) -> String {
        let selectedRuleIds = Array(Set(selected.ruleHits.map(\.ruleId))).sorted()

        if let topHit = selected.ruleHits.first {
            var summary = "偏好 profile \(profileVersion) 命中 \(selectedRuleIds.joined(separator: "、"))，因此更建议先点「\(selected.baseline.action.displayName)」：\(topHit.explanation)"
            if let copyStyleDirective {
                summary += " 备注可继续沿用 \(copyStyleDirective.ruleId) 的结论前置写法。"
            }
            return summary
        }

        if let copyStyleDirective {
            return "偏好 profile \(profileVersion) 当前未改动动作排序，但备注建议沿用 \(copyStyleDirective.ruleId) 的结论前置写法。"
        }

        return "偏好 profile \(profileVersion) 已加载，但当前审阅建议未命中可解释规则。"
    }

    private func buildSuggestedReviewNote(
        action: TeacherQuickFeedbackAction,
        context: ReviewSuggestionContext,
        prefersConciseCopy: Bool
    ) -> String? {
        switch action {
        case .approved:
            return "结果可接受。"
        case .rejected:
            return prefersConciseCopy
                ? "结果暂不可接受，需继续修正。"
                : "结果暂不可接受，建议继续修正后再交老师确认。"
        case .fixLocator:
            return prefersConciseCopy
                ? "建议先修 locator，当前更像定位锚点失效。"
                : "建议先修 locator，当前失败更像定位锚点或语义目标失效。"
        case .reteach:
            return prefersConciseCopy
                ? "建议重新示教，当前步骤本身需要刷新。"
                : "建议重新示教，当前步骤本身已经偏离老师原始做法。"
        case .tooDangerous:
            return context.hasBlocked
                ? "本次执行已触发风险阻断，建议继续保留人工确认。"
                : "本次执行风险偏高，建议继续保留人工确认。"
        case .wrongOrder:
            return prefersConciseCopy
                ? "当前更像顺序问题，建议按老师原始顺序重试。"
                : "当前更像顺序问题，建议按老师原始步骤顺序重新执行。"
        case .wrongStyle:
            return prefersConciseCopy
                ? "当前操作风格不对，建议改回老师常用做法。"
                : "当前操作风格不对，建议改回老师常用的交互习惯与表达方式。"
        case .needsRevision:
            return "当前结果仍需继续修正。"
        }
    }

    private func loadLatestReviewPreferenceProfile() -> PreferenceProfile? {
        guard let preferencesRootDirectory else {
            return nil
        }

        return try? PreferenceMemoryStore(
            preferencesRootDirectory: preferencesRootDirectory,
            fileManager: fileManager
        ).loadLatestProfileSnapshot()?.profile
    }

    private func matchedReviewCopyStyleDirective(
        directives: [PreferenceProfileDirective],
        context: ReviewSuggestionContext
    ) -> PreferenceProfileDirective? {
        directives.first { directive in
            interpretedReviewPreference(for: directive, context: context) == .conciseCopy
                && scopeMatchScore(for: directive.scope, context: context) > 0
        }
    }

    private func interpretedReviewPreference(
        for directive: PreferenceProfileDirective,
        context: ReviewSuggestionContext
    ) -> ReviewDirectiveInterpretation {
        let actionText = normalized(directive.proposedAction)
        let text = normalized([
            directive.proposedAction,
            directive.hint,
            directive.statement
        ].compactMap { $0 }.joined(separator: " "))

        if directive.type == .style,
           containsAnyToken(
                actionText,
                tokens: [
                    "shortenreviewcopy",
                    "shorten review copy",
                    "concise review copy",
                    "conclusion first",
                    "conclusion-first"
                ]
           ) {
            return .conciseCopy
        }

        if containsAnyToken(
            actionText,
            tokens: [
                "updateskilllocator",
                "update skill locator",
                "refresh skill locator",
                "refresh_skill_locator",
                "relocalize",
                "repair_before_reteach"
            ]
        ) {
            return .fixLocatorFirst
        }

        if containsAnyToken(
            actionText,
            tokens: [
                "reteachcurrentstep",
                "reteach",
                "re teach",
                "re-teach"
            ]
        ) {
            return .reteachFirst
        }

        if containsAnyToken(
            actionText,
            tokens: [
                "require_teacher_confirmation",
                "teacher confirmation",
                "confirmation",
                "guard"
            ]
        ) {
            return .riskFirst
        }

        if containsAnyToken(
            text,
            tokens: [
                "先修",
                "先修 locator",
                "refresh semantic",
                "repair locator",
                "修 locator",
                "semantic anchor",
                "text anchor",
                "locator"
            ]
        ) {
            return .fixLocatorFirst
        }

        if containsAnyToken(
            text,
            tokens: [
                "reteach",
                "re teach",
                "re-teach",
                "重新示教",
                "重新教学"
            ]
        ) {
            return .reteachFirst
        }

        if containsAnyToken(
            text,
            tokens: [
                "teacher confirmation",
                "confirmation gated",
                "高风险",
                "太危险",
                "危险",
                "risk"
            ]
        ) {
            return .riskFirst
        }

        if containsAnyToken(
            text,
            tokens: [
                "order",
                "sequence",
                "before",
                "after",
                "顺序",
                "先后"
            ]
        ) {
            return .wrongOrderFirst
        }

        if containsAnyToken(
            text,
            tokens: [
                "style",
                "tone",
                "keyboard",
                "shortcut",
                "menu traversal",
                "风格",
                "习惯"
            ]
        ) {
            return .wrongStyleFirst
        }

        switch directive.type {
        case .outcome:
            return context.overallStatus == .succeeded ? .resultApproved : .resultRejected
        case .procedure:
            return .wrongOrderFirst
        case .locator:
            return .fixLocatorFirst
        case .style:
            return .wrongStyleFirst
        case .risk:
            return .riskFirst
        case .repair:
            return .fixLocatorFirst
        }
    }

    private func buildReviewRuleHitExplanation(
        directive: PreferenceProfileDirective,
        interpretation: ReviewDirectiveInterpretation,
        action: TeacherQuickFeedbackAction,
        priorityDelta: Double
    ) -> String {
        let direction = priorityDelta >= 0 ? "抬高" : "压低"
        return "规则 \(directive.ruleId) \(interpretation.userFacingSummary(for: action))，因此\(direction)了该建议的优先级。"
    }

    private func scopeMatchScore(
        for scope: PreferenceSignalScopeReference,
        context: ReviewSuggestionContext
    ) -> Double {
        switch scope.level {
        case .global:
            return 0.72
        case .app:
            return appScopeScore(scope: scope, context: context)
        case .taskFamily:
            return familyScopeScore(ruleFamily: scope.taskFamily, currentFamily: context.taskFamily)
        case .skillFamily:
            return familyScopeScore(ruleFamily: scope.skillFamily, currentFamily: context.skillFamily)
        case .windowPattern:
            return windowScopeScore(scope: scope, context: context)
        }
    }

    private func appScopeScore(
        scope: PreferenceSignalScopeReference,
        context: ReviewSuggestionContext
    ) -> Double {
        let scopedBundle = normalized(scope.appBundleId)
        let scopedName = normalized(scope.appName)
        let currentBundle = normalized(context.appBundleId)
        let currentName = normalized(context.appName)

        if !scopedBundle.isEmpty, scopedBundle == currentBundle {
            return 1.0
        }
        if !scopedName.isEmpty, scopedName == currentName {
            return 0.82
        }
        return 0
    }

    private func familyScopeScore(
        ruleFamily: String?,
        currentFamily: String?
    ) -> Double {
        let lhs = normalized(ruleFamily)
        let rhs = normalized(currentFamily)
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return 0
        }

        if lhs == rhs {
            return 1.0
        }
        if lhs.contains(rhs) || rhs.contains(lhs) {
            return 0.84
        }
        return 0
    }

    private func windowScopeScore(
        scope: PreferenceSignalScopeReference,
        context: ReviewSuggestionContext
    ) -> Double {
        let appScore = appScopeScore(scope: scope, context: context)
        if scope.appBundleId != nil || scope.appName != nil, appScore <= 0 {
            return 0
        }

        guard let pattern = scope.windowPattern,
              let currentWindow = context.windowTitle,
              !currentWindow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return 0
        }

        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(currentWindow.startIndex..<currentWindow.endIndex, in: currentWindow)
            if regex.firstMatch(in: currentWindow, options: [], range: range) != nil {
                return 1.0
            }
        }

        let lhs = normalized(pattern)
        let rhs = normalized(currentWindow)
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return 0
        }
        if lhs == rhs {
            return 0.92
        }
        if lhs.contains(rhs) || rhs.contains(lhs) {
            return 0.8
        }
        return max(0, bigramSimilarity(lhs, rhs) - 0.18)
    }

    private func overallResultStatus(
        selectedLog: ExecutionLogSummary,
        comparisonRows: [ExecutionReviewComparisonRow]
    ) -> ExecutionReviewResultStatus {
        if comparisonRows.contains(where: { $0.resultStatus == .blocked }) {
            return .blocked
        }
        if comparisonRows.contains(where: { $0.resultStatus == .failed }) {
            return .failed
        }
        if !comparisonRows.isEmpty,
           comparisonRows.allSatisfy({ $0.resultStatus == .succeeded }) {
            return .succeeded
        }
        return resultStatus(from: selectedLog)
    }

    private func baselineSuggestionSort(
        lhs: ExecutionReviewSuggestionBaseline,
        rhs: ExecutionReviewSuggestionBaseline
    ) -> Bool {
        if lhs.basePriority == rhs.basePriority {
            return suggestionActionOrder(lhs.action) < suggestionActionOrder(rhs.action)
        }
        return lhs.basePriority > rhs.basePriority
    }

    private func rankedReviewSuggestionSort(
        lhs: RankedExecutionReviewSuggestion,
        rhs: RankedExecutionReviewSuggestion
    ) -> Bool {
        if lhs.finalPriority == rhs.finalPriority {
            return baselineSuggestionSort(lhs: lhs.baseline, rhs: rhs.baseline)
        }
        return lhs.finalPriority > rhs.finalPriority
    }

    private func reviewSuggestionRuleHitSort(
        lhs: ExecutionReviewSuggestionRuleHit,
        rhs: ExecutionReviewSuggestionRuleHit
    ) -> Bool {
        let lhsMagnitude = abs(lhs.priorityDelta)
        let rhsMagnitude = abs(rhs.priorityDelta)
        if lhsMagnitude == rhsMagnitude {
            return lhs.ruleId < rhs.ruleId
        }
        return lhsMagnitude > rhsMagnitude
    }

    private func suggestionActionOrder(_ action: TeacherQuickFeedbackAction) -> Int {
        switch action {
        case .fixLocator:
            return 0
        case .reteach:
            return 1
        case .tooDangerous:
            return 2
        case .wrongOrder:
            return 3
        case .wrongStyle:
            return 4
        case .rejected:
            return 5
        case .approved:
            return 6
        case .needsRevision:
            return 7
        }
    }

    private func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    private func normalized(_ value: String?) -> String {
        guard let value else {
            return ""
        }

        let lowered = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else {
            return ""
        }

        let filteredScalars = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar)
                || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }

        return String(filteredScalars)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func containsAnyToken(
        _ text: String,
        tokens: [String]
    ) -> Bool {
        tokens.contains { token in
            text.contains(normalized(token))
        }
    }

    private func keywordMatchScore(
        _ text: String,
        tokens: [String]
    ) -> Double {
        guard !text.isEmpty else {
            return 0
        }

        let hitCount = tokens.reduce(into: 0) { partial, token in
            if text.contains(normalized(token)) {
                partial += 1
            }
        }
        guard hitCount > 0 else {
            return 0
        }
        return min(1.0, Double(hitCount) / Double(max(tokens.count, 1)))
    }

    private func tokenOverlapScore(
        _ lhs: String,
        _ rhs: String
    ) -> Double {
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else {
            return 0
        }

        let sharedCount = lhsTokens.intersection(rhsTokens).count
        let denominator = max(lhsTokens.count, rhsTokens.count)
        guard denominator > 0 else {
            return 0
        }
        return Double(sharedCount) / Double(denominator)
    }

    private func bigramSimilarity(
        _ lhs: String,
        _ rhs: String
    ) -> Double {
        let lhsBigrams = bigrams(for: lhs)
        let rhsBigrams = bigrams(for: rhs)
        guard !lhsBigrams.isEmpty, !rhsBigrams.isEmpty else {
            return 0
        }

        let sharedCount = lhsBigrams.intersection(rhsBigrams).count
        let denominator = max(lhsBigrams.count, rhsBigrams.count)
        guard denominator > 0 else {
            return 0
        }
        return Double(sharedCount) / Double(denominator)
    }

    private func bigrams(for text: String) -> Set<String> {
        let characters = Array(text.replacingOccurrences(of: " ", with: ""))
        guard characters.count > 1 else {
            return []
        }

        var values = Set<String>()
        for index in 0..<(characters.count - 1) {
            values.insert(String([characters[index], characters[index + 1]]))
        }
        return values
    }

    private func loadSkill(atDirectoryPath path: String) -> ResolvedSkill? {
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else {
            return nil
        }

        let skillURL = directory.appendingPathComponent("openstaff-skill.json", isDirectory: false)
        guard let data = try? Data(contentsOf: skillURL),
              let payload = try? decoder.decode(SkillBundlePayload.self, from: data) else {
            return nil
        }

        let scopeId = skillRoots.first(where: { directory.path.hasPrefix($0.directory.path) })?.scopeId ?? "unknown"
        return ResolvedSkill(
            skillId: "\(scopeId)|\(directory.path)",
            directory: directory,
            payload: payload
        )
    }

    private func loadAllSkills() -> [ResolvedSkill] {
        var skills: [ResolvedSkill] = []
        for root in skillRoots {
            guard fileManager.fileExists(atPath: root.directory.path) else {
                continue
            }
            guard let enumerator = fileManager.enumerator(
                at: root.directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let directory as URL in enumerator {
                let skillURL = directory.appendingPathComponent("openstaff-skill.json", isDirectory: false)
                guard fileManager.fileExists(atPath: skillURL.path),
                      let data = try? Data(contentsOf: skillURL),
                      let payload = try? decoder.decode(SkillBundlePayload.self, from: data) else {
                    continue
                }

                skills.append(
                    ResolvedSkill(
                        skillId: "\(root.scopeId)|\(directory.path)",
                        directory: directory,
                        payload: payload
                    )
                )
            }
        }
        return skills
    }

    private func loadKnowledgeItem(id: String) -> KnowledgeItem? {
        loadKnowledgeItems().first(where: { $0.knowledgeItemId == id })
    }

    private func loadKnowledgeItems() -> [KnowledgeItem] {
        listFiles(withExtension: "json", under: knowledgeRootDirectory)
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else {
                    return nil
                }
                return try? decoder.decode(KnowledgeItem.self, from: data)
            }
    }

    private func extractSkillName(from logs: [ExecutionLogSummary]) -> String? {
        for log in logs {
            if let skillName = log.skillName, !skillName.isEmpty {
                return skillName
            }
            if let skillId = log.skillId, !skillId.isEmpty, !skillId.contains("-step-") {
                return skillId
            }
            let prefix = "Manual UI run started for skill "
            if log.message.hasPrefix(prefix) {
                return log.message
                    .replacingOccurrences(of: prefix, with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            }
        }
        return nil
    }

    private func resultStatus(from log: ExecutionLogSummary) -> ExecutionReviewResultStatus {
        if let errorCode = log.errorCode?.lowercased(), errorCode.contains("blocked") {
            return .blocked
        }
        let normalizedStatus = log.status.lowercased()
        if normalizedStatus.contains("blocked") {
            return .blocked
        }
        if normalizedStatus.contains("failed") {
            return .failed
        }
        if normalizedStatus.contains("completed") || normalizedStatus.contains("succeeded") {
            return .succeeded
        }
        return .unknown
    }

    private func resultStatus(from result: StudentStepExecutionResult?) -> ExecutionReviewResultStatus {
        guard let result else {
            return .unknown
        }

        switch result.status {
        case .succeeded:
            return .succeeded
        case .failed:
            return .failed
        case .blocked:
            return .blocked
        }
    }

    private func actualResultDetail(
        from result: ReviewExecutionResult?,
        fallbackMessage: String
    ) -> String {
        guard let result else {
            return "暂无结构化结果。\n参考步骤：\(fallbackMessage)"
        }

        if let errorCode = result.errorCode, !errorCode.isEmpty {
            return "\(result.output)\nerrorCode: \(errorCode)"
        }
        return result.output
    }

    private func locatorSummary(mapping: SkillBundleStepMapping?) -> String {
        guard let mapping else {
            return "locator: 未携带 provenance"
        }

        let targetSummary = mapping.semanticTargets.isEmpty
            ? "none"
            : mapping.semanticTargets.map { target in
                let title = target.elementTitle ?? target.textAnchor ?? target.axPath ?? target.elementIdentifier ?? "unknown"
                return "\(target.locatorType.rawValue): \(title)"
            }
            .joined(separator: ", ")

        let coordinateSummary: String
        if let coordinate = mapping.coordinate {
            coordinateSummary = "coordinate: \(Int(coordinate.x)),\(Int(coordinate.y))"
        } else {
            coordinateSummary = "coordinate: none"
        }

        return [
            "mapping: \(mapping.knowledgeStepId ?? "none")",
            "locator: \(targetSummary)",
            coordinateSummary
        ].joined(separator: "\n")
    }

    private func preferredLocatorRepairType(for mapping: SkillBundleStepMapping?) -> SkillRepairActionType? {
        guard let mapping else {
            return .updateSkillLocator
        }

        let preferred = mapping.preferredLocatorType
        if preferred == .coordinateFallback {
            return .relocalize
        }

        if mapping.semanticTargets.contains(where: { $0.locatorType == .coordinateFallback }) {
            return .relocalize
        }

        return .updateSkillLocator
    }

    private func inferMode(component: String?) -> OpenStaffMode? {
        let value = component?.lowercased() ?? ""
        if value.contains("student") || value.contains("openclaw") {
            return .student
        }
        if value.contains("assist") {
            return .assist
        }
        if value.contains("capture") || value.contains("knowledge") || value.contains("task") || value.contains("orchestrator") {
            return .teaching
        }
        return nil
    }

    private func inferMode(fromFileName fileName: String) -> OpenStaffMode {
        if fileName.contains("student") || fileName.contains("openclaw") {
            return .student
        }
        if fileName.contains("assist") {
            return .assist
        }
        return .teaching
    }

    private func listFiles(withExtension pathExtension: String, under root: URL) -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == pathExtension {
            urls.append(fileURL)
        }
        return urls
    }

    private static func dateKey(from timestamp: String) -> String {
        let candidate = String(timestamp.prefix(10))
        if candidate.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil {
            return candidate
        }
        return ExecutionReviewDateSupport.dayString(from: Date())
    }
}

private struct ReviewExecutionResult {
    let status: ExecutionReviewResultStatus
    let output: String
    let errorCode: String?
}

private struct SkillResultLookup {
    let bySkillStepId: [String: ReviewExecutionResult]
    let byOrder: [Int: ReviewExecutionResult]
}

private struct ResolvedSkill {
    let skillId: String
    let directory: URL
    let payload: SkillBundlePayload
}

private struct ExecutionReviewSuggestionResult {
    let suggestions: [ExecutionReviewSuggestion]
    let decision: ExecutionReviewSuggestionDecision?
}

private struct ExecutionReviewSuggestionBaseline {
    let action: TeacherQuickFeedbackAction
    let basePriority: Double
    let baseReason: String
}

private struct RankedExecutionReviewSuggestion {
    let baseline: ExecutionReviewSuggestionBaseline
    let finalPriority: Double
    let ruleHits: [ExecutionReviewSuggestionRuleHit]
}

private struct ReviewSuggestionContext {
    let appBundleId: String?
    let appName: String?
    let windowTitle: String?
    let taskFamily: String?
    let skillFamily: String?
    let overallStatus: ExecutionReviewResultStatus
    let hasFailure: Bool
    let hasBlocked: Bool
    let likelyLocatorScore: Double
    let likelyOrderScore: Double
    let likelyStyleScore: Double
    let riskSignalScore: Double

    init(
        selectedLog: ExecutionLogSummary,
        comparisonRows: [ExecutionReviewComparisonRow],
        knowledgeItem: KnowledgeItem?,
        skill: ResolvedSkill?,
        locatorRepairAction: ExecutionReviewRepairAction?,
        reteachAction: ExecutionReviewRepairAction?,
        overallStatus: ExecutionReviewResultStatus
    ) {
        let normalizedMessage = ReviewSuggestionContext.normalizeText(
            [selectedLog.message, selectedLog.errorCode].compactMap { $0 }.joined(separator: " ")
        )
        let mismatchScores = comparisonRows.map { row in
            let teacher = ReviewSuggestionContext.normalizeText(row.teacherStep.detail)
            let skill = ReviewSuggestionContext.normalizeText(row.skillStep.detail)
            let overlap = ReviewSuggestionContext.tokenOverlap(teacher, skill)
            return max(0, 1.0 - overlap)
        }
        let maxMismatch = mismatchScores.max() ?? 0
        let failureRows = comparisonRows.filter { row in
            row.resultStatus == .failed || row.resultStatus == .blocked
        }

        self.appBundleId = skill?.payload.mappedOutput.context.appBundleId ?? knowledgeItem?.context.appBundleId
        self.appName = skill?.payload.mappedOutput.context.appName ?? knowledgeItem?.context.appName
        self.windowTitle = skill?.payload.mappedOutput.context.windowTitle ?? knowledgeItem?.context.windowTitle
        self.taskFamily = skill?.payload.provenance?.skillBuild?.taskFamily
        self.skillFamily = skill?.payload.provenance?.skillBuild?.skillFamily
        self.overallStatus = overallStatus
        self.hasFailure = overallStatus == .failed || overallStatus == .blocked
        self.hasBlocked = overallStatus == .blocked

        let locatorKeywordScore = ReviewSuggestionContext.keywordScore(
            normalizedMessage,
            tokens: [
                "locator",
                "anchor",
                "semantic",
                "not found",
                "target",
                "未找到",
                "定位",
                "锚点"
            ]
        )
        let locatorRowScore = failureRows.contains(where: { $0.preferredRepairActionType != nil }) ? 0.28 : 0
        let repairScore = locatorRepairAction != nil ? 0.24 : 0
        self.likelyLocatorScore = min(1.0, locatorKeywordScore + locatorRowScore + repairScore)

        let orderKeywordScore = ReviewSuggestionContext.keywordScore(
            normalizedMessage,
            tokens: ["order", "sequence", "before", "after", "顺序", "先后"]
        )
        let multiStepScore = comparisonRows.count > 1 && overallStatus != .succeeded ? 0.18 : 0
        self.likelyOrderScore = min(1.0, orderKeywordScore + multiStepScore + max(0, maxMismatch - 0.72))

        let styleKeywordScore = ReviewSuggestionContext.keywordScore(
            normalizedMessage,
            tokens: ["style", "keyboard", "shortcut", "menu", "风格", "习惯", "话术"]
        )
        let reteachBias = reteachAction != nil ? 0.1 : 0
        self.likelyStyleScore = min(1.0, styleKeywordScore + max(0, maxMismatch - 0.58) + reteachBias)

        let riskKeywordScore = ReviewSuggestionContext.keywordScore(
            normalizedMessage,
            tokens: ["blocked", "danger", "risk", "confirmation", "阻断", "危险", "高风险"]
        )
        self.riskSignalScore = min(1.0, riskKeywordScore + (overallStatus == .blocked ? 0.34 : 0))
    }

    private static func normalizeText(_ value: String?) -> String {
        guard let value else {
            return ""
        }

        let lowered = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else {
            return ""
        }

        let filteredScalars = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar)
                || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }

        return String(filteredScalars)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func tokenOverlap(
        _ lhs: String,
        _ rhs: String
    ) -> Double {
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else {
            return 0
        }

        let sharedCount = lhsTokens.intersection(rhsTokens).count
        let denominator = max(lhsTokens.count, rhsTokens.count)
        guard denominator > 0 else {
            return 0
        }
        return Double(sharedCount) / Double(denominator)
    }

    private static func keywordScore(
        _ text: String,
        tokens: [String]
    ) -> Double {
        guard !text.isEmpty else {
            return 0
        }

        let normalizedTokens = tokens.map(normalizeText)
        let hitCount = normalizedTokens.reduce(into: 0) { partial, token in
            if !token.isEmpty, text.contains(token) {
                partial += 1
            }
        }
        guard hitCount > 0 else {
            return 0
        }

        return min(1.0, Double(hitCount) / Double(max(normalizedTokens.count, 1)))
    }
}

private enum ReviewDirectiveInterpretation: Equatable {
    case fixLocatorFirst
    case reteachFirst
    case riskFirst
    case wrongOrderFirst
    case wrongStyleFirst
    case resultApproved
    case resultRejected
    case conciseCopy

    func affinity(
        for action: TeacherQuickFeedbackAction,
        context: ReviewSuggestionContext
    ) -> Double {
        switch self {
        case .fixLocatorFirst:
            switch action {
            case .fixLocator:
                return 1.0
            case .reteach:
                return -0.42
            case .rejected:
                return 0.12
            default:
                return 0
            }
        case .reteachFirst:
            switch action {
            case .reteach:
                return 1.0
            case .fixLocator:
                return -0.34
            case .rejected:
                return 0.08
            default:
                return 0
            }
        case .riskFirst:
            switch action {
            case .tooDangerous:
                return context.hasBlocked ? 1.0 : 0.86
            case .rejected:
                return 0.24
            case .approved:
                return -0.62
            default:
                return 0
            }
        case .wrongOrderFirst:
            switch action {
            case .wrongOrder:
                return 1.0
            case .rejected:
                return 0.14
            case .approved:
                return -0.26
            default:
                return 0
            }
        case .wrongStyleFirst:
            switch action {
            case .wrongStyle:
                return 1.0
            case .rejected:
                return 0.12
            case .approved:
                return -0.18
            default:
                return 0
            }
        case .resultApproved:
            switch action {
            case .approved:
                return 0.92
            case .rejected:
                return -0.24
            default:
                return 0
            }
        case .resultRejected:
            switch action {
            case .rejected:
                return 0.9
            case .approved:
                return -0.36
            default:
                return 0
            }
        case .conciseCopy:
            return 0
        }
    }

    func userFacingSummary(for action: TeacherQuickFeedbackAction) -> String {
        switch self {
        case .fixLocatorFirst:
            if action == .fixLocator {
                return "体现出你通常更倾向于先修 locator"
            }
            return "更倾向于先修 locator，而不是当前动作"
        case .reteachFirst:
            if action == .reteach {
                return "体现出你通常更倾向于直接重新示教"
            }
            return "更倾向于先重新示教，而不是当前动作"
        case .riskFirst:
            if action == .tooDangerous {
                return "体现出你会先把高风险结果标成“太危险”"
            }
            return "要求对高风险结果更谨慎"
        case .wrongOrderFirst:
            if action == .wrongOrder {
                return "体现出你通常会先指出顺序问题"
            }
            return "更关注顺序偏差，而不是当前动作"
        case .wrongStyleFirst:
            if action == .wrongStyle {
                return "体现出你通常会先指出风格偏差"
            }
            return "更关注风格偏差，而不是当前动作"
        case .resultApproved:
            return "更强调结果达成时直接通过"
        case .resultRejected:
            return "更强调结果未达成时直接驳回"
        case .conciseCopy:
            return "要求审阅文案保持结论前置"
        }
    }
}

private struct ExecutionLogRecord: Decodable {
    let timestamp: String
    let traceId: String?
    let sessionId: String
    let taskId: String?
    let status: String
    let message: String
    let component: String?
    let errorCode: String?
    let planId: String?
    let skillId: String?
    let planStepId: String?
    let skillName: String?
    let skillDirectoryPath: String?
    let sourceKnowledgeItemId: String?
    let sourceStepId: String?
    let stepId: String?
    let actionType: String?
    let exitCode: Int32?
}

private struct TeacherFeedbackReadRecord: Decodable {
    let feedbackId: String
    let timestamp: String
    let decision: TeacherFeedbackDecision
    let note: String?
    let logEntryId: String
}

private enum ExecutionReviewDateSupport {
    static func date(from value: String) -> Date? {
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: value) {
            return date
        }

        let formatterWithoutFractional = ISO8601DateFormatter()
        formatterWithoutFractional.formatOptions = [.withInternetDateTime]
        return formatterWithoutFractional.date(from: value)
    }

    static func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
