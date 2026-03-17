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

    var hasActionableRepair: Bool {
        locatorRepairAction != nil || reteachAction != nil
    }
}

struct ExecutionReviewStore {
    private let logsRootDirectory: URL
    private let feedbackRootDirectory: URL
    private let reportsRootDirectory: URL
    private let knowledgeRootDirectory: URL
    private let skillRoots: [ExecutionReviewSkillRoot]
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        logsRootDirectory: URL,
        feedbackRootDirectory: URL,
        reportsRootDirectory: URL,
        knowledgeRootDirectory: URL,
        skillRoots: [ExecutionReviewSkillRoot],
        fileManager: FileManager = .default
    ) {
        self.logsRootDirectory = logsRootDirectory
        self.feedbackRootDirectory = feedbackRootDirectory
        self.reportsRootDirectory = reportsRootDirectory
        self.knowledgeRootDirectory = knowledgeRootDirectory
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
            reteachAction: reteachAction
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
