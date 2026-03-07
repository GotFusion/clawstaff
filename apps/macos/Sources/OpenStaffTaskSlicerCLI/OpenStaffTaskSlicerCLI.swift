import Foundation

@main
struct OpenStaffTaskSlicerCLI {
    static func main() {
        do {
            let options = try TaskSlicerCLIOptions.parse(arguments: CommandLine.arguments)

            if options.showHelp {
                printHelp()
                return
            }

            let loader = SessionRawEventLoader()
            let loaded = try loader.load(
                sessionId: options.sessionId,
                dateKey: options.dateKey,
                rawRootDirectory: options.rawRootDirectoryURL
            )

            let slicer = SessionTaskSlicer(policy: options.slicingPolicy)
            let chunks = try slicer.slice(events: loaded.events, sessionId: options.sessionId)

            let writer = TaskChunkWriter()
            let outputFiles = try writer.write(
                chunks: chunks,
                dateKey: options.dateKey,
                knowledgeRootDirectory: options.knowledgeRootDirectoryURL
            )

            print("Task slicing completed. sessionId=\(options.sessionId) date=\(options.dateKey) events=\(loaded.events.count) chunks=\(chunks.count)")
            print("Source files=\(loaded.sourceFiles.count) output files=\(outputFiles.count)")
            print("Knowledge output directory: \(options.knowledgeRootDirectoryURL.appendingPathComponent(options.dateKey, isDirectory: true).path)")

            if options.printJSON {
                let encoder = JSONEncoder()
                for chunk in chunks {
                    let data = try encoder.encode(chunk)
                    if let line = String(data: data, encoding: .utf8) {
                        print(line)
                    }
                }
            }
        } catch {
            print("Task slicer failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    static func printHelp() {
        print("""
        OpenStaffTaskSlicerCLI

        Usage:
          make slice ARGS="--session-id session-20260307-a1 --date 2026-03-07"

        Flags:
          --session-id <id>               Session ID to slice (lowercase letters, numbers, hyphen).
          --date <yyyy-mm-dd>             Date partition to read/write. Default: today (local timezone).
          --raw-root <path>               Raw event root directory. Default: data/raw-events
          --knowledge-root <path>         Knowledge output root directory. Default: data/knowledge
          --idle-gap-seconds <n>          Idle threshold in seconds for splitting. Default: 20
          --disable-context-switch-split  Disable app/window context-switch split rule.
          --json                          Print generated TaskChunk JSON lines.
          --help                          Show this help message.
        """)
    }
}

struct TaskSlicerCLIOptions {
    static let defaultRawRoot = "data/raw-events"
    static let defaultKnowledgeRoot = "data/knowledge"
    static let defaultIdleGapSeconds: TimeInterval = 20

    let sessionId: String
    let dateKey: String
    let rawRootDirectory: String
    let knowledgeRootDirectory: String
    let idleGapSeconds: TimeInterval
    let splitOnContextSwitch: Bool
    let printJSON: Bool
    let showHelp: Bool

    static func parse(arguments: [String]) throws -> TaskSlicerCLIOptions {
        var sessionId: String?
        var dateKey = defaultDateKey()
        var rawRootDirectory = defaultRawRoot
        var knowledgeRootDirectory = defaultKnowledgeRoot
        var idleGapSeconds = defaultIdleGapSeconds
        var splitOnContextSwitch = true
        var printJSON = false
        var showHelp = false

        var index = 1
        while index < arguments.count {
            let token = arguments[index]

            switch token {
            case "--session-id":
                index += 1
                guard index < arguments.count else {
                    throw TaskSlicerCLIOptionError.missingValue("--session-id")
                }
                sessionId = arguments[index]
            case "--date":
                index += 1
                guard index < arguments.count else {
                    throw TaskSlicerCLIOptionError.missingValue("--date")
                }
                dateKey = arguments[index]
            case "--raw-root":
                index += 1
                guard index < arguments.count else {
                    throw TaskSlicerCLIOptionError.missingValue("--raw-root")
                }
                rawRootDirectory = arguments[index]
            case "--knowledge-root":
                index += 1
                guard index < arguments.count else {
                    throw TaskSlicerCLIOptionError.missingValue("--knowledge-root")
                }
                knowledgeRootDirectory = arguments[index]
            case "--idle-gap-seconds":
                index += 1
                guard index < arguments.count else {
                    throw TaskSlicerCLIOptionError.missingValue("--idle-gap-seconds")
                }

                guard let parsed = TimeInterval(arguments[index]), parsed >= 0 else {
                    throw TaskSlicerCLIOptionError.invalidValue("--idle-gap-seconds", arguments[index])
                }
                idleGapSeconds = parsed
            case "--disable-context-switch-split":
                splitOnContextSwitch = false
            case "--json":
                printJSON = true
            case "--help", "-h":
                showHelp = true
            default:
                throw TaskSlicerCLIOptionError.unknownFlag(token)
            }

            index += 1
        }

        if showHelp {
            return TaskSlicerCLIOptions(
                sessionId: sessionId ?? "session-placeholder",
                dateKey: dateKey,
                rawRootDirectory: rawRootDirectory,
                knowledgeRootDirectory: knowledgeRootDirectory,
                idleGapSeconds: idleGapSeconds,
                splitOnContextSwitch: splitOnContextSwitch,
                printJSON: printJSON,
                showHelp: showHelp
            )
        }

        guard let resolvedSessionId = sessionId else {
            throw TaskSlicerCLIOptionError.missingRequired("--session-id")
        }
        guard isValidSessionId(resolvedSessionId) else {
            throw TaskSlicerCLIOptionError.invalidValue("--session-id", resolvedSessionId)
        }
        guard isValidDateKey(dateKey) else {
            throw TaskSlicerCLIOptionError.invalidValue("--date", dateKey)
        }

        return TaskSlicerCLIOptions(
            sessionId: resolvedSessionId,
            dateKey: dateKey,
            rawRootDirectory: rawRootDirectory,
            knowledgeRootDirectory: knowledgeRootDirectory,
            idleGapSeconds: idleGapSeconds,
            splitOnContextSwitch: splitOnContextSwitch,
            printJSON: printJSON,
            showHelp: showHelp
        )
    }

    private static func defaultDateKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }

    private static func isValidSessionId(_ value: String) -> Bool {
        let pattern = "^[a-z0-9-]+$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isValidDateKey(_ value: String) -> Bool {
        let pattern = "^\\d{4}-\\d{2}-\\d{2}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    var rawRootDirectoryURL: URL {
        resolve(path: rawRootDirectory)
    }

    var knowledgeRootDirectoryURL: URL {
        resolve(path: knowledgeRootDirectory)
    }

    var slicingPolicy: TaskSlicingPolicy {
        TaskSlicingPolicy(
            idleGapSeconds: idleGapSeconds,
            splitOnContextSwitch: splitOnContextSwitch
        )
    }

    private func resolve(path: String) -> URL {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return URL(fileURLWithPath: path, relativeTo: currentDirectory).standardizedFileURL
    }
}

enum TaskSlicerCLIOptionError: LocalizedError {
    case missingValue(String)
    case missingRequired(String)
    case invalidValue(String, String)
    case unknownFlag(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .missingRequired(let flag):
            return "Missing required flag: \(flag). Use --help to see usage."
        case .invalidValue(let flag, let value):
            return "Invalid value for \(flag): \(value)."
        case .unknownFlag(let flag):
            return "Unknown flag: \(flag). Use --help to see supported flags."
        }
    }
}
