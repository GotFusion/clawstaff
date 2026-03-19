import Foundation

public struct FileSystemLearningGateway: LearningGatewayServing {
    public let repositoryRootDirectory: URL
    public let learningRootDirectory: URL
    public let preferencesRootDirectory: URL

    private let preferenceStore: PreferenceMemoryStore
    private let assemblyStore: PolicyAssemblyDecisionStore
    private let exportRunner: any LearningGatewayExportScriptRunning
    private let nowProvider: () -> Date
    private let formatter: ISO8601DateFormatter

    public init(
        repositoryRootDirectory: URL,
        learningRootDirectory: URL,
        preferencesRootDirectory: URL,
        fileManager: FileManager = .default,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.init(
            repositoryRootDirectory: repositoryRootDirectory,
            learningRootDirectory: learningRootDirectory,
            preferencesRootDirectory: preferencesRootDirectory,
            preferenceStore: PreferenceMemoryStore(
                preferencesRootDirectory: preferencesRootDirectory,
                fileManager: fileManager
            ),
            assemblyStore: PolicyAssemblyDecisionStore(
                preferencesRootDirectory: preferencesRootDirectory,
                fileManager: fileManager
            ),
            exportRunner: FoundationLearningGatewayExportScriptRunner(fileManager: fileManager),
            nowProvider: nowProvider
        )
    }

    init(
        repositoryRootDirectory: URL,
        learningRootDirectory: URL,
        preferencesRootDirectory: URL,
        preferenceStore: PreferenceMemoryStore,
        assemblyStore: PolicyAssemblyDecisionStore,
        exportRunner: any LearningGatewayExportScriptRunning,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.repositoryRootDirectory = repositoryRootDirectory.standardizedFileURL
        self.learningRootDirectory = learningRootDirectory.standardizedFileURL
        self.preferencesRootDirectory = preferencesRootDirectory.standardizedFileURL
        self.preferenceStore = preferenceStore
        self.assemblyStore = assemblyStore
        self.exportRunner = exportRunner
        self.nowProvider = nowProvider

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        self.formatter = formatter
    }

    public func listRules(_ request: PreferencesListRulesRequest) throws -> PreferencesListRulesResponse {
        let query = PreferenceRuleQuery(
            appBundleId: request.filter.appBundleId,
            taskFamily: request.filter.taskFamily,
            skillFamily: request.filter.skillFamily,
            includeInactive: request.filter.includeInactive
        )
        let rules = try preferenceStore.loadRules(matching: query)

        return PreferencesListRulesResponse(
            generatedAt: timestamp(),
            rules: rules,
            latestProfileSnapshot: try latestProfileSnapshot(
                includeSnapshot: request.includeLatestProfileSnapshot
            )
        )
    }

    public func listAssemblyDecisions(
        _ request: PreferencesListAssemblyDecisionsRequest
    ) throws -> PreferencesListAssemblyDecisionsResponse {
        let query = PolicyAssemblyDecisionQuery(
            date: request.filter.date,
            targetModule: request.filter.targetModule,
            sessionId: request.filter.sessionId,
            taskId: request.filter.taskId,
            traceId: request.filter.traceId
        )
        let decisions = try assemblyStore.loadDecisions(matching: query)

        return PreferencesListAssemblyDecisionsResponse(
            generatedAt: timestamp(),
            decisions: decisions,
            latestProfileSnapshot: try latestProfileSnapshot(
                includeSnapshot: request.includeLatestProfileSnapshot
            )
        )
    }

    public func exportBundle(_ request: PreferencesExportBundleRequest) throws -> PreferencesExportBundleResponse {
        let outputDirectoryPath = resolvedPath(request.outputDirectoryPath)
        guard !outputDirectoryPath.isEmpty else {
            throw LearningGatewayError.invalidRequest("Learning gateway export requires a non-empty outputDirectoryPath.")
        }
        let scriptRequest = LearningGatewayExportScriptRequest(
            repositoryRootDirectory: repositoryRootDirectory,
            relativeScriptPath: "scripts/learning/export_learning_bundle.py",
            arguments: exportArguments(
                outputDirectoryPath: outputDirectoryPath,
                request: request
            )
        )
        let scriptOutput = try exportRunner.run(request: scriptRequest)
        let data = Data(scriptOutput.stdout.utf8)

        let decoded: LearningGatewayBundleExportScriptResult
        do {
            decoded = try JSONDecoder().decode(LearningGatewayBundleExportScriptResult.self, from: data)
        } catch {
            throw LearningGatewayError.invalidScriptOutput(
                "Failed to decode learning bundle export JSON: \(error.localizedDescription)"
            )
        }

        return PreferencesExportBundleResponse(
            bundleId: decoded.bundleId,
            bundlePath: decoded.bundlePath,
            manifestPath: decoded.manifestPath,
            verificationPath: decoded.verificationPath,
            counts: decoded.counts.contractValue,
            indexes: decoded.indexes.contractValue,
            passed: decoded.passed,
            issues: decoded.issues.map(\.contractValue)
        )
    }

    private func latestProfileSnapshot(includeSnapshot: Bool) throws -> PreferenceProfileSnapshot? {
        guard includeSnapshot else {
            return nil
        }
        return try preferenceStore.loadLatestProfileSnapshot()
    }

    private func exportArguments(
        outputDirectoryPath: String,
        request: PreferencesExportBundleRequest
    ) -> [String] {
        var arguments = [
            "--learning-root", learningRootDirectory.path,
            "--preferences-root", preferencesRootDirectory.path,
            "--output", outputDirectoryPath,
            "--json"
        ]

        if let bundleId = request.bundleId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleId.isEmpty {
            arguments += ["--bundle-id", bundleId]
        }

        request.filter.sessionIds.forEach { sessionId in
            arguments += ["--session-id", sessionId]
        }
        request.filter.taskIds.forEach { taskId in
            arguments += ["--task-id", taskId]
        }
        request.filter.turnIds.forEach { turnId in
            arguments += ["--turn-id", turnId]
        }

        if request.overwrite {
            arguments.append("--overwrite")
        }

        return arguments
    }

    private func resolvedPath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL.path
        }

        return URL(
            fileURLWithPath: trimmed,
            relativeTo: repositoryRootDirectory
        ).standardizedFileURL.path
    }

    private func timestamp() -> String {
        formatter.string(from: nowProvider())
    }
}

protocol LearningGatewayExportScriptRunning {
    func run(request: LearningGatewayExportScriptRequest) throws -> LearningGatewayExportScriptOutput
}

struct LearningGatewayExportScriptRequest {
    let repositoryRootDirectory: URL
    let relativeScriptPath: String
    let arguments: [String]
}

struct LearningGatewayExportScriptOutput {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

struct FoundationLearningGatewayExportScriptRunner: LearningGatewayExportScriptRunning {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func run(request: LearningGatewayExportScriptRequest) throws -> LearningGatewayExportScriptOutput {
        let scriptURL = request.repositoryRootDirectory
            .appendingPathComponent(request.relativeScriptPath, isDirectory: false)
            .standardizedFileURL

        guard fileManager.fileExists(atPath: scriptURL.path) else {
            throw LearningGatewayError.scriptMissing(scriptURL.path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env", isDirectory: false)
        process.arguments = ["python3", scriptURL.path] + request.arguments
        process.currentDirectoryURL = request.repositoryRootDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw LearningGatewayError.pythonRuntimeUnavailable
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let failureText = [stderr, stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " | ")
            throw LearningGatewayError.scriptExecutionFailed(
                scriptURL.path,
                process.terminationStatus,
                failureText
            )
        }

        return LearningGatewayExportScriptOutput(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}

enum LearningGatewayError: LocalizedError {
    case invalidRequest(String)
    case pythonRuntimeUnavailable
    case scriptMissing(String)
    case scriptExecutionFailed(String, Int32, String)
    case invalidScriptOutput(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let message):
            return message
        case .pythonRuntimeUnavailable:
            return "Python runtime unavailable for learning gateway bundle export."
        case .scriptMissing(let path):
            return "Learning gateway export script is missing: \(path)"
        case .scriptExecutionFailed(let path, let exitCode, let stderr):
            return "Learning gateway export script failed: \(path) (exit=\(exitCode)) \(stderr)"
        case .invalidScriptOutput(let detail):
            return detail
        }
    }
}

private struct LearningGatewayBundleExportScriptResult: Decodable {
    let bundleId: String
    let bundlePath: String
    let manifestPath: String
    let verificationPath: String
    let counts: LearningGatewayBundleExportScriptCounts
    let indexes: LearningGatewayBundleExportScriptIndexes
    let passed: Bool
    let issues: [LearningGatewayBundleExportScriptIssue]
}

private struct LearningGatewayBundleExportScriptCounts: Decodable {
    let turns: LearningBundleCategoryCount
    let evidence: LearningBundleCategoryCount
    let signals: LearningBundleCategoryCount
    let rules: LearningBundleCategoryCount
    let profiles: LearningBundleCategoryCount
    let audit: LearningBundleCategoryCount

    var contractValue: LearningBundleExportCounts {
        LearningBundleExportCounts(
            turns: turns,
            evidence: evidence,
            signals: signals,
            rules: rules,
            profiles: profiles,
            audit: audit
        )
    }
}

private struct LearningGatewayBundleExportScriptIndexes: Decodable {
    let turnIds: [String]
    let evidenceIds: [String]
    let signalIds: [String]
    let ruleIds: [String]
    let profileVersions: [String]
    let auditIds: [String]
    let latestProfileVersion: String?
    let latestProfileUpdatedAt: String?

    var contractValue: LearningBundleExportIndexes {
        LearningBundleExportIndexes(
            turnIds: turnIds,
            evidenceIds: evidenceIds,
            signalIds: signalIds,
            ruleIds: ruleIds,
            profileVersions: profileVersions,
            auditIds: auditIds,
            latestProfileVersion: latestProfileVersion,
            latestProfileUpdatedAt: latestProfileUpdatedAt
        )
    }
}

private struct LearningGatewayBundleExportScriptIssue: Decodable {
    let severity: String
    let code: String
    let message: String
    let path: String?
    let category: String?
    let recordId: String?
    let field: String?

    var contractValue: LearningGatewayIssue {
        LearningGatewayIssue(
            severity: severity,
            code: code,
            message: message,
            path: path,
            category: category,
            recordId: recordId,
            field: field
        )
    }
}
