import Foundation

@main
struct OpenStaffReplayVerifyCLI {
    static func main() {
        do {
            let options = try ReplayVerifyCLIOptions.parse(arguments: CommandLine.arguments)

            if options.showHelp {
                printHelp()
                return
            }

            let knowledgeItems = try ReplayKnowledgeLoader().load(from: options.knowledgeInputURL)
            let snapshot = try options.snapshotProvider().snapshot()
            let verifier = ReplayVerifier(
                snapshotProvider: StaticReplayEnvironmentSnapshotProvider(snapshot: snapshot)
            )

            let reports = knowledgeItems.map { verifier.verify(item: $0, snapshot: snapshot) }
            let batch = ReplayVerificationBatchReport(
                generatedAt: currentTimestamp(),
                snapshot: snapshot,
                reports: reports,
                summary: ReplayBatchSummary(reports: reports)
            )

            if options.printJSON {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(batch)
                if let text = String(data: data, encoding: .utf8) {
                    print(text)
                }
            } else {
                printSummary(batch: batch)
            }

            if batch.summary.degradedSteps > 0 || batch.summary.failedSteps > 0 {
                Foundation.exit(2)
            }
        } catch {
            print("Replay verify CLI failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    static func printHelp() {
        print("""
        OpenStaffReplayVerifyCLI

        Usage:
          make replay-verify ARGS="--knowledge core/knowledge/examples/knowledge-item.sample.json --snapshot core/executor/examples/replay-environment.sample.json --json"

        Flags:
          --knowledge <path>        KnowledgeItem JSON file or directory.
          --snapshot <path>         Optional replay snapshot JSON file. If omitted, capture the current frontmost window via AX.
          --json                    Print structured verification report.
          --help                    Show this help message.

        Exit codes:
          0                         All checked steps resolved successfully.
          1                         CLI/input error.
          2                         At least one step failed or degraded to coordinate fallback.
        """)
    }

    static func printSummary(batch: ReplayVerificationBatchReport) {
        print(
            "Replay verification finished. " +
            "items=\(batch.summary.knowledgeItemCount) " +
            "checked=\(batch.summary.checkedSteps) " +
            "resolved=\(batch.summary.resolvedSteps) " +
            "degraded=\(batch.summary.degradedSteps) " +
            "failed=\(batch.summary.failedSteps)"
        )

        for report in batch.reports {
            print(
                "knowledgeItem=\(report.knowledgeItemId) " +
                "resolved=\(report.summary.resolvedSteps) " +
                "degraded=\(report.summary.degradedSteps) " +
                "failed=\(report.summary.failedSteps)"
            )

            for step in report.steps {
                print(
                    "  [\(step.status.rawValue)] \(step.stepId) " +
                    "locator=\(step.matchedLocatorType?.rawValue ?? "-") " +
                    "reason=\(step.failureReason?.rawValue ?? "-")"
                )
            }
        }
    }
}

struct ReplayVerifyCLIOptions {
    let knowledgeInputPath: String
    let snapshotPath: String?
    let printJSON: Bool
    let showHelp: Bool

    static func parse(arguments: [String]) throws -> ReplayVerifyCLIOptions {
        var knowledgeInputPath: String?
        var snapshotPath: String?
        var printJSON = false
        var showHelp = false

        var index = 1
        while index < arguments.count {
            let token = arguments[index]

            switch token {
            case "--knowledge":
                index += 1
                guard index < arguments.count else {
                    throw ReplayVerifyCLIOptionError.missingValue("--knowledge")
                }
                knowledgeInputPath = arguments[index]
            case "--snapshot":
                index += 1
                guard index < arguments.count else {
                    throw ReplayVerifyCLIOptionError.missingValue("--snapshot")
                }
                snapshotPath = arguments[index]
            case "--json":
                printJSON = true
            case "--help", "-h":
                showHelp = true
            default:
                throw ReplayVerifyCLIOptionError.unknownFlag(token)
            }

            index += 1
        }

        if showHelp {
            return ReplayVerifyCLIOptions(
                knowledgeInputPath: knowledgeInputPath ?? "core/knowledge/examples/knowledge-item.sample.json",
                snapshotPath: snapshotPath,
                printJSON: printJSON,
                showHelp: true
            )
        }

        guard let knowledgeInputPath else {
            throw ReplayVerifyCLIOptionError.missingRequired("--knowledge")
        }

        return ReplayVerifyCLIOptions(
            knowledgeInputPath: knowledgeInputPath,
            snapshotPath: snapshotPath,
            printJSON: printJSON,
            showHelp: false
        )
    }

    var knowledgeInputURL: URL {
        resolve(path: knowledgeInputPath)
    }

    func snapshotProvider() throws -> any ReplayEnvironmentSnapshotProviding {
        if let snapshotPath {
            let snapshot = try ReplayEnvironmentSnapshotLoader().load(from: resolve(path: snapshotPath))
            return StaticReplayEnvironmentSnapshotProvider(snapshot: snapshot)
        }

        return LiveReplayEnvironmentSnapshotProvider()
    }

    private func resolve(path: String) -> URL {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return URL(fileURLWithPath: path, relativeTo: currentDirectory).standardizedFileURL
    }
}

struct ReplayKnowledgeLoader {
    private let fileManager: FileManager
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(from inputURL: URL) throws -> [KnowledgeItem] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
            throw ReplayKnowledgeLoaderError.inputNotFound(path: inputURL.path)
        }

        if isDirectory.boolValue {
            let files: [URL]
            do {
                files = try fileManager.contentsOfDirectory(
                    at: inputURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                throw ReplayKnowledgeLoaderError.listDirectoryFailed(path: inputURL.path, underlying: error)
            }

            return try files
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map(decodeItem(from:))
        }

        return [try decodeItem(from: inputURL)]
    }

    private func decodeItem(from fileURL: URL) throws -> KnowledgeItem {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ReplayKnowledgeLoaderError.readFileFailed(path: fileURL.path, underlying: error)
        }

        do {
            return try decoder.decode(KnowledgeItem.self, from: data)
        } catch {
            throw ReplayKnowledgeLoaderError.decodeFailed(path: fileURL.path, underlying: error)
        }
    }
}

struct ReplayEnvironmentSnapshotLoader {
    private let decoder = JSONDecoder()

    func load(from fileURL: URL) throws -> ReplayEnvironmentSnapshot {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ReplaySnapshotLoaderError.readFileFailed(path: fileURL.path, underlying: error)
        }

        do {
            return try decoder.decode(ReplayEnvironmentSnapshot.self, from: data)
        } catch {
            throw ReplaySnapshotLoaderError.decodeFailed(path: fileURL.path, underlying: error)
        }
    }
}

struct ReplayVerificationBatchReport: Codable {
    let generatedAt: String
    let snapshot: ReplayEnvironmentSnapshot
    let reports: [ReplayVerificationReport]
    let summary: ReplayBatchSummary
}

struct ReplayBatchSummary: Codable {
    let knowledgeItemCount: Int
    let totalSteps: Int
    let checkedSteps: Int
    let skippedSteps: Int
    let resolvedSteps: Int
    let degradedSteps: Int
    let failedSteps: Int

    init(reports: [ReplayVerificationReport]) {
        knowledgeItemCount = reports.count
        totalSteps = reports.reduce(0) { $0 + $1.summary.totalSteps }
        checkedSteps = reports.reduce(0) { $0 + $1.summary.checkedSteps }
        skippedSteps = reports.reduce(0) { $0 + $1.summary.skippedSteps }
        resolvedSteps = reports.reduce(0) { $0 + $1.summary.resolvedSteps }
        degradedSteps = reports.reduce(0) { $0 + $1.summary.degradedSteps }
        failedSteps = reports.reduce(0) { $0 + $1.summary.failedSteps }
    }
}

enum ReplayVerifyCLIOptionError: LocalizedError {
    case missingValue(String)
    case missingRequired(String)
    case unknownFlag(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .missingRequired(let flag):
            return "Missing required flag: \(flag). Use --help to see usage."
        case .unknownFlag(let flag):
            return "Unknown flag: \(flag). Use --help to see supported flags."
        }
    }
}

enum ReplayKnowledgeLoaderError: LocalizedError {
    case inputNotFound(path: String)
    case listDirectoryFailed(path: String, underlying: Error)
    case readFileFailed(path: String, underlying: Error)
    case decodeFailed(path: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .inputNotFound(let path):
            return "Knowledge input path not found: \(path)"
        case .listDirectoryFailed(let path, let underlying):
            return "Failed to list knowledge directory \(path): \(underlying.localizedDescription)"
        case .readFileFailed(let path, let underlying):
            return "Failed to read knowledge item \(path): \(underlying.localizedDescription)"
        case .decodeFailed(let path, let underlying):
            return "Failed to decode knowledge item \(path): \(underlying.localizedDescription)"
        }
    }
}

enum ReplaySnapshotLoaderError: LocalizedError {
    case readFileFailed(path: String, underlying: Error)
    case decodeFailed(path: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .readFileFailed(let path, let underlying):
            return "Failed to read replay snapshot \(path): \(underlying.localizedDescription)"
        case .decodeFailed(let path, let underlying):
            return "Failed to decode replay snapshot \(path): \(underlying.localizedDescription)"
        }
    }
}

private func currentTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}
