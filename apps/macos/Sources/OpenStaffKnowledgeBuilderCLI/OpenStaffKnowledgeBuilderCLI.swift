import Foundation

@main
struct OpenStaffKnowledgeBuilderCLI {
    static func main() {
        do {
            let options = try KnowledgeBuilderCLIOptions.parse(arguments: CommandLine.arguments)

            if options.showHelp {
                printHelp()
                return
            }

            let loader = TaskChunkLoader()
            let loaded = try loader.load(
                sessionId: options.sessionId,
                dateKey: options.dateKey,
                taskChunkRootDirectory: options.taskChunkRootDirectoryURL
            )

            let builder = KnowledgeItemBuilder()
            let items = loaded.chunks.map { builder.build(from: $0) }

            let writer = KnowledgeItemWriter()
            let outputFiles = try writer.write(
                items: items,
                dateKey: options.dateKey,
                knowledgeRootDirectory: options.knowledgeRootDirectoryURL
            )

            print("Knowledge build completed. sessionId=\(options.sessionId) date=\(options.dateKey) chunks=\(loaded.chunks.count) items=\(items.count)")
            print("Task chunk files=\(loaded.sourceFiles.count) output files=\(outputFiles.count)")
            print("Knowledge output directory: \(options.knowledgeRootDirectoryURL.appendingPathComponent(options.dateKey, isDirectory: true).path)")

            if options.printJSON {
                let encoder = JSONEncoder()
                for item in items {
                    let data = try encoder.encode(item)
                    if let line = String(data: data, encoding: .utf8) {
                        print(line)
                    }
                }
            }
        } catch {
            print("Knowledge builder failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    static func printHelp() {
        print("""
        OpenStaffKnowledgeBuilderCLI

        Usage:
          make knowledge ARGS="--session-id session-20260307-a1 --date 2026-03-07"

        Flags:
          --session-id <id>         Session ID to build knowledge from.
          --date <yyyy-mm-dd>       Date partition to read/write. Default: today (local timezone).
          --task-chunk-root <path>  Task chunk root directory. Default: data/task-chunks
          --knowledge-root <path>   Knowledge output root directory. Default: data/knowledge
          --json                    Print generated KnowledgeItem JSON lines.
          --help                    Show this help message.
        """)
    }
}

struct KnowledgeBuilderCLIOptions {
    static let defaultTaskChunkRoot = "data/task-chunks"
    static let defaultKnowledgeRoot = "data/knowledge"

    let sessionId: String
    let dateKey: String
    let taskChunkRootDirectory: String
    let knowledgeRootDirectory: String
    let printJSON: Bool
    let showHelp: Bool

    static func parse(arguments: [String]) throws -> KnowledgeBuilderCLIOptions {
        var sessionId: String?
        var dateKey = defaultDateKey()
        var taskChunkRootDirectory = defaultTaskChunkRoot
        var knowledgeRootDirectory = defaultKnowledgeRoot
        var printJSON = false
        var showHelp = false

        var index = 1
        while index < arguments.count {
            let token = arguments[index]

            switch token {
            case "--session-id":
                index += 1
                guard index < arguments.count else {
                    throw KnowledgeBuilderCLIOptionError.missingValue("--session-id")
                }
                sessionId = arguments[index]
            case "--date":
                index += 1
                guard index < arguments.count else {
                    throw KnowledgeBuilderCLIOptionError.missingValue("--date")
                }
                dateKey = arguments[index]
            case "--task-chunk-root":
                index += 1
                guard index < arguments.count else {
                    throw KnowledgeBuilderCLIOptionError.missingValue("--task-chunk-root")
                }
                taskChunkRootDirectory = arguments[index]
            case "--knowledge-root":
                index += 1
                guard index < arguments.count else {
                    throw KnowledgeBuilderCLIOptionError.missingValue("--knowledge-root")
                }
                knowledgeRootDirectory = arguments[index]
            case "--json":
                printJSON = true
            case "--help", "-h":
                showHelp = true
            default:
                throw KnowledgeBuilderCLIOptionError.unknownFlag(token)
            }

            index += 1
        }

        if showHelp {
            return KnowledgeBuilderCLIOptions(
                sessionId: sessionId ?? "session-placeholder",
                dateKey: dateKey,
                taskChunkRootDirectory: taskChunkRootDirectory,
                knowledgeRootDirectory: knowledgeRootDirectory,
                printJSON: printJSON,
                showHelp: showHelp
            )
        }

        guard let resolvedSessionId = sessionId else {
            throw KnowledgeBuilderCLIOptionError.missingRequired("--session-id")
        }
        guard isValidSessionId(resolvedSessionId) else {
            throw KnowledgeBuilderCLIOptionError.invalidValue("--session-id", resolvedSessionId)
        }
        guard isValidDateKey(dateKey) else {
            throw KnowledgeBuilderCLIOptionError.invalidValue("--date", dateKey)
        }

        return KnowledgeBuilderCLIOptions(
            sessionId: resolvedSessionId,
            dateKey: dateKey,
            taskChunkRootDirectory: taskChunkRootDirectory,
            knowledgeRootDirectory: knowledgeRootDirectory,
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

    var taskChunkRootDirectoryURL: URL {
        resolve(path: taskChunkRootDirectory)
    }

    var knowledgeRootDirectoryURL: URL {
        resolve(path: knowledgeRootDirectory)
    }

    private func resolve(path: String) -> URL {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return URL(fileURLWithPath: path, relativeTo: currentDirectory).standardizedFileURL
    }
}

enum KnowledgeBuilderCLIOptionError: LocalizedError {
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
