import Foundation

enum LearnedSkillOpenClawRuntime {
    static let displayName = "Semantic-Only OpenClaw CLI"

    static func currentExecutablePath() -> String? {
        locateExecutable()?.path
    }

    static func locateExecutable(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let override = environment["OPENCLAW_CLI_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let overrideURL = URL(fileURLWithPath: override, isDirectory: false)
            if fileManager.isExecutableFile(atPath: overrideURL.path) {
                return overrideURL
            }
        }

        let repositoryRoot = OpenStaffWorkspacePaths.repositoryRoot
        let candidates = [
            Bundle.main.executableURL?.deletingLastPathComponent()
                .appendingPathComponent("OpenStaffOpenClawCLI", isDirectory: false),
            repositoryRoot.appendingPathComponent("apps/macos/.build/debug/OpenStaffOpenClawCLI", isDirectory: false),
            repositoryRoot.appendingPathComponent("apps/macos/.build/arm64-apple-macosx/debug/OpenStaffOpenClawCLI", isDirectory: false),
            repositoryRoot.appendingPathComponent("apps/macos/.build/x86_64-apple-macosx/debug/OpenStaffOpenClawCLI", isDirectory: false),
        ]

        for candidate in candidates.compactMap({ $0 }) {
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

struct LearnedSkillOpenClawExecutionResult {
    let status: String
    let totalSteps: Int
    let succeededSteps: Int
    let failedSteps: Int
    let blockedSteps: Int
    let summary: String
    let logFilePath: String
}

enum LearnedSkillOpenClawBridge {
    static func run(
        skillDirectoryPath: String,
        traceId: String,
        sessionId: String,
        taskId: String?,
        teacherConfirmed: Bool,
        timeoutSeconds: Int = 90
    ) throws -> LearnedSkillOpenClawExecutionResult {
        guard let executableURL = LearnedSkillOpenClawRuntime.locateExecutable() else {
            throw LearnedSkillOpenClawBridgeError.executableMissing
        }

        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = OpenStaffWorkspacePaths.repositoryRoot

        var arguments = [
            "--skill-dir",
            skillDirectoryPath,
            "--trace-id",
            traceId,
            "--session-id",
            sessionId,
            "--json-result",
        ]
        if let taskId, !taskId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--task-id", taskId]
        }
        if teacherConfirmed {
            arguments.append("--teacher-confirmed")
        }
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw LearnedSkillOpenClawBridgeError.launchFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(Double(timeoutSeconds))
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw LearnedSkillOpenClawBridgeError.timedOut(timeoutSeconds)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard let data = stdout.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let payload = try? JSONDecoder().decode(OpenClawCLIResultPayload.self, from: data) else {
            throw LearnedSkillOpenClawBridgeError.invalidOutput(
                stderr.isEmpty ? stdout.trimmingCharacters(in: .whitespacesAndNewlines) : stderr
            )
        }

        return LearnedSkillOpenClawExecutionResult(
            status: payload.status,
            totalSteps: payload.totalSteps,
            succeededSteps: payload.succeededSteps,
            failedSteps: payload.failedSteps,
            blockedSteps: payload.blockedSteps,
            summary: payload.summary,
            logFilePath: payload.review?.logFilePath ?? payload.skillDirectoryPath
        )
    }
}

private struct OpenClawCLIResultPayload: Decodable {
    let status: String
    let totalSteps: Int
    let succeededSteps: Int
    let failedSteps: Int
    let blockedSteps: Int
    let summary: String
    let skillDirectoryPath: String
    let review: OpenClawCLIReviewPayload?
}

private struct OpenClawCLIReviewPayload: Decodable {
    let logFilePath: String
}

private enum LearnedSkillOpenClawBridgeError: LocalizedError {
    case executableMissing
    case launchFailed(String)
    case invalidOutput(String)
    case timedOut(Int)

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            return "未找到 OpenStaffOpenClawCLI。请先执行 `make build`，或设置 `OPENCLAW_CLI_PATH` 指向已编译的 semantic-only CLI。"
        case .launchFailed(let reason):
            return "启动 OpenStaffOpenClawCLI 失败：\(reason)"
        case .invalidOutput(let output):
            if output.isEmpty {
                return "OpenStaffOpenClawCLI 未返回可解析的结构化结果。"
            }
            return "OpenStaffOpenClawCLI 返回了无法解析的结果：\(output)"
        case .timedOut(let seconds):
            return "OpenStaffOpenClawCLI 执行超时（\(seconds) 秒）。"
        }
    }
}
