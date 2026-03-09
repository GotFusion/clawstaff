import Foundation

@main
struct OpenStaffDemoCLI {
    static func main() {
        do {
            let options = try DemoCLIOptions.parse(arguments: CommandLine.arguments)

            if options.showHelp {
                printHelp()
                return
            }

            let runner = DemoRunner(options: options)
            try runner.run()
        } catch {
            print("OpenStaffDemoCLI failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    static func printHelp() {
        print("""
        OpenStaffDemoCLI

        Usage:
          swift run --package-path apps/macos OpenStaffDemoCLI

        Flags:
          --knowledge-item <path>   KnowledgeItem JSON path. Default: core/knowledge/examples/knowledge-item.sample.json
          --goal <text>             Student mode goal. Default: 在 Safari 中复现点击流程
          --output-root <path>      Demo output root. Default: /tmp/openstaff-demo-experience
          --skip-orchestrator       Skip orchestrator teaching -> assist step.
          --help                    Show this help message.
        """)
    }
}

struct DemoCLIOptions {
    let knowledgeItemPath: String
    let goal: String
    let outputRootPath: String
    let skipOrchestrator: Bool
    let showHelp: Bool

    var knowledgeItemURL: URL {
        resolve(path: knowledgeItemPath)
    }

    var outputRootURL: URL {
        resolve(path: outputRootPath)
    }

    static func parse(arguments: [String]) throws -> DemoCLIOptions {
        var knowledgeItemPath = "core/knowledge/examples/knowledge-item.sample.json"
        var goal = "在 Safari 中复现点击流程"
        var outputRootPath = "/tmp/openstaff-demo-experience"
        var skipOrchestrator = false
        var showHelp = false

        var index = 1
        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--knowledge-item":
                index += 1
                guard index < arguments.count else {
                    throw DemoCLIOptionError.missingValue("--knowledge-item")
                }
                knowledgeItemPath = arguments[index]
            case "--goal":
                index += 1
                guard index < arguments.count else {
                    throw DemoCLIOptionError.missingValue("--goal")
                }
                goal = arguments[index]
            case "--output-root":
                index += 1
                guard index < arguments.count else {
                    throw DemoCLIOptionError.missingValue("--output-root")
                }
                outputRootPath = arguments[index]
            case "--skip-orchestrator":
                skipOrchestrator = true
            case "--help", "-h":
                showHelp = true
            default:
                throw DemoCLIOptionError.unknownFlag(token)
            }
            index += 1
        }

        if !showHelp {
            if goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw DemoCLIOptionError.invalidValue("--goal", goal)
            }
        }

        return DemoCLIOptions(
            knowledgeItemPath: knowledgeItemPath,
            goal: goal,
            outputRootPath: outputRootPath,
            skipOrchestrator: skipOrchestrator,
            showHelp: showHelp
        )
    }

    private func resolve(path: String) -> URL {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return URL(fileURLWithPath: path, relativeTo: currentDirectory).standardizedFileURL
    }
}

enum DemoCLIOptionError: LocalizedError {
    case missingValue(String)
    case invalidValue(String, String)
    case unknownFlag(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .invalidValue(let flag, let value):
            return "Invalid value for \(flag): \(value)."
        case .unknownFlag(let flag):
            return "Unknown flag: \(flag). Use --help to see supported flags."
        }
    }
}

private struct DemoCommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private final class DemoRunner {
    private let options: DemoCLIOptions
    private let fileManager = FileManager.default

    init(options: DemoCLIOptions) {
        self.options = options
    }

    func run() throws {
        let repoRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let packageRoot = repoRoot.appendingPathComponent("apps/macos", isDirectory: true)
        let knowledgeItem = options.knowledgeItemURL

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: knowledgeItem.path, isDirectory: &isDir), !isDir.boolValue else {
            throw DemoRunnerError.missingKnowledgeItem(knowledgeItem.path)
        }

        let outputRoot = options.outputRootURL
        if fileManager.fileExists(atPath: outputRoot.path) {
            try fileManager.removeItem(at: outputRoot)
        }
        try fileManager.createDirectory(at: outputRoot, withIntermediateDirectories: true, attributes: nil)
        let logsRoot = outputRoot.appendingPathComponent("logs", isDirectory: true)
        let reportsRoot = outputRoot.appendingPathComponent("reports", isDirectory: true)
        let stepOutputRoot = outputRoot.appendingPathComponent("step-outputs", isDirectory: true)
        try fileManager.createDirectory(at: logsRoot, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: reportsRoot, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: stepOutputRoot, withIntermediateDirectories: true, attributes: nil)

        let timestamp = currentTimestamp()

        print("OpenStaff Demo Experience")
        print("outputRoot=\(outputRoot.path)")
        print("knowledgeItem=\(knowledgeItem.path)")
        print("goal=\(options.goal)")

        let orchestratorBinary = try resolveExecutable(named: "OpenStaffOrchestratorCLI", packageRoot: packageRoot)
        let assistBinary = try resolveExecutable(named: "OpenStaffAssistCLI", packageRoot: packageRoot)
        let studentBinary = try resolveExecutable(named: "OpenStaffStudentCLI", packageRoot: packageRoot)

        var summary: [String: Any] = [
            "schemaVersion": "openstaff.demo-experience.v0",
            "startedAt": timestamp,
            "outputRoot": outputRoot.path,
            "knowledgeItem": knowledgeItem.path,
            "goal": options.goal,
            "steps": [[String: Any]]()
        ]

        if !options.skipOrchestrator {
            let args = [
                "--from", "teaching",
                "--to", "assist",
                "--session-id", "session-demo",
                "--teacher-confirmed",
                "--knowledge-ready",
                "--trace-id", "trace-demo-orchestrator",
                "--timestamp", timestamp,
                "--json-decision"
            ]
            let result = try runStep(
                stepName: "orchestrator-transition",
                executable: orchestratorBinary,
                arguments: args,
                outputRoot: stepOutputRoot
            )
            try ensureSuccess(step: "orchestrator-transition", result: result)
            appendStep(
                summary: &summary,
                stepName: "orchestrator-transition",
                exitCode: result.exitCode,
                stdoutPath: stepOutputRoot.appendingPathComponent("orchestrator-transition.stdout.log").path,
                stderrPath: stepOutputRoot.appendingPathComponent("orchestrator-transition.stderr.log").path
            )
        }

        let assistArgs = [
            "--knowledge-item", knowledgeItem.path,
            "--from", "teaching",
            "--auto-confirm", "yes",
            "--logs-root", logsRoot.path,
            "--trace-id", "trace-demo-assist",
            "--timestamp", timestamp,
            "--json-result"
        ]
        let assistResult = try runStep(
            stepName: "assist-loop",
            executable: assistBinary,
            arguments: assistArgs,
            outputRoot: stepOutputRoot
        )
        try ensureSuccess(step: "assist-loop", result: assistResult)
        appendStep(
            summary: &summary,
            stepName: "assist-loop",
            exitCode: assistResult.exitCode,
            stdoutPath: stepOutputRoot.appendingPathComponent("assist-loop.stdout.log").path,
            stderrPath: stepOutputRoot.appendingPathComponent("assist-loop.stderr.log").path
        )

        let studentArgs = [
            "--goal", options.goal,
            "--knowledge", knowledgeItem.path,
            "--from", "assist",
            "--logs-root", logsRoot.path,
            "--reports-root", reportsRoot.path,
            "--trace-id", "trace-demo-student",
            "--timestamp", timestamp,
            "--json-result"
        ]
        let studentResult = try runStep(
            stepName: "student-loop",
            executable: studentBinary,
            arguments: studentArgs,
            outputRoot: stepOutputRoot
        )
        try ensureSuccess(step: "student-loop", result: studentResult)
        appendStep(
            summary: &summary,
            stepName: "student-loop",
            exitCode: studentResult.exitCode,
            stdoutPath: stepOutputRoot.appendingPathComponent("student-loop.stdout.log").path,
            stderrPath: stepOutputRoot.appendingPathComponent("student-loop.stderr.log").path
        )

        summary["finishedAt"] = currentTimestamp()
        let summaryURL = outputRoot.appendingPathComponent("demo-summary.json", isDirectory: false)
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: summaryURL, options: [.atomic])

        print("")
        print("Demo completed successfully.")
        print("Summary: \(summaryURL.path)")
        print("Logs root: \(logsRoot.path)")
        print("Reports root: \(reportsRoot.path)")
    }

    private func resolveExecutable(named name: String, packageRoot: URL) throws -> URL {
        let candidates: [URL] = [
            packageRoot.appendingPathComponent(".build/debug/\(name)", isDirectory: false),
            packageRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/\(name)", isDirectory: false),
            packageRoot.appendingPathComponent(".build/x86_64-apple-macosx/debug/\(name)", isDirectory: false)
        ]

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        throw DemoRunnerError.missingExecutable(name)
    }

    private func runStep(
        stepName: String,
        executable: URL,
        arguments: [String],
        outputRoot: URL
    ) throws -> DemoCommandResult {
        print("")
        print("[STEP] \(stepName)")
        print("cmd: \(executable.path) \(arguments.joined(separator: " "))")

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        try stdout.write(
            to: outputRoot.appendingPathComponent("\(stepName).stdout.log"),
            atomically: true,
            encoding: .utf8
        )
        try stderr.write(
            to: outputRoot.appendingPathComponent("\(stepName).stderr.log"),
            atomically: true,
            encoding: .utf8
        )

        if !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print(stdout)
        }
        if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print(stderr)
        }

        return DemoCommandResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }

    private func ensureSuccess(step: String, result: DemoCommandResult) throws {
        if result.exitCode != 0 {
            throw DemoRunnerError.stepFailed(step: step, exitCode: result.exitCode)
        }
    }

    private func appendStep(
        summary: inout [String: Any],
        stepName: String,
        exitCode: Int32,
        stdoutPath: String,
        stderrPath: String
    ) {
        var steps = summary["steps"] as? [[String: Any]] ?? []
        steps.append([
            "step": stepName,
            "exitCode": Int(exitCode),
            "stdoutPath": stdoutPath,
            "stderrPath": stderrPath
        ])
        summary["steps"] = steps
    }

    private func currentTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

enum DemoRunnerError: LocalizedError {
    case missingKnowledgeItem(String)
    case missingExecutable(String)
    case stepFailed(step: String, exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case .missingKnowledgeItem(let path):
            return "Knowledge item file not found: \(path)"
        case .missingExecutable(let name):
            return "Missing compiled executable: \(name). Run `make demo-build` first."
        case .stepFailed(let step, let exitCode):
            return "Demo step '\(step)' failed with exit code \(exitCode)."
        }
    }
}
