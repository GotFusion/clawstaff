import Foundation

@main
struct OpenStaffPreferenceProfileCLI {
    static func main() {
        do {
            let options = try PreferenceProfileCLIOptions.parse(arguments: CommandLine.arguments)

            if options.showHelp {
                printHelp()
                return
            }

            let store = PreferenceMemoryStore(preferencesRootDirectory: options.preferencesRootURL)
            let builder = PreferenceProfileBuilder()

            let output: PreferenceProfileCLIOutput
            switch (options.rebuild, options.persist) {
            case (false, false):
                guard let snapshot = try store.loadLatestProfileSnapshot() else {
                    throw PreferenceProfileCLIError.noProfileSnapshotFound(options.preferencesRootURL.path)
                }
                output = PreferenceProfileCLIOutput(
                    mode: .loadedLatest,
                    preferencesRootPath: options.preferencesRootURL.path,
                    snapshot: snapshot,
                    moduleSummaries: builder.summaries(for: snapshot.profile)
                )
            case (true, false):
                let result = try builder.rebuild(
                    using: store,
                    profileVersion: options.profileVersion,
                    generatedAt: options.timestamp,
                    note: options.note
                )
                output = PreferenceProfileCLIOutput(
                    mode: .rebuiltEphemeral,
                    preferencesRootPath: options.preferencesRootURL.path,
                    snapshot: result.snapshot,
                    moduleSummaries: result.moduleSummaries
                )
            case (true, true):
                let result = try builder.rebuildAndStore(
                    using: store,
                    actor: options.actor,
                    profileVersion: options.profileVersion,
                    generatedAt: options.timestamp,
                    note: options.note
                )
                output = PreferenceProfileCLIOutput(
                    mode: .rebuiltAndPersisted,
                    preferencesRootPath: options.preferencesRootURL.path,
                    snapshot: result.snapshot,
                    moduleSummaries: result.moduleSummaries
                )
            case (false, true):
                throw PreferenceProfileCLIError.persistRequiresRebuild
            }

            if options.printJSON {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(output)
                if let text = String(data: data, encoding: .utf8) {
                    print(text)
                }
            } else {
                printSummary(output)
            }
        } catch {
            print("Preference profile CLI failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    static func printHelp() {
        print("""
        OpenStaffPreferenceProfileCLI

        Usage:
          make preference-profile ARGS="--preferences-root data/preferences --rebuild --persist --json"
          make preference-profile ARGS="--preferences-root data/preferences --json"

        Flags:
          --preferences-root <path>   Preference store root. Default: data/preferences
          --rebuild                   Rebuild a profile snapshot from currently active rules.
          --persist                   Persist the rebuilt snapshot and refresh latest pointer.
          --profile-version <id>      Optional explicit profile version.
          --timestamp <iso8601>       Snapshot timestamp. Default: now.
          --actor <id>                Audit actor used when persisting. Default: cli
          --note <text>               Optional snapshot note.
          --json                      Print structured JSON output.
          --help                      Show this help message.
        """)
    }

    fileprivate static func printSummary(_ output: PreferenceProfileCLIOutput) {
        let snapshot = output.snapshot
        print(
            "Preference profile \(output.mode.rawValue). " +
            "profileVersion=\(snapshot.profileVersion) " +
            "activeRules=\(snapshot.profile.activeRuleIds.count) " +
            "directives=\(snapshot.profile.totalDirectiveCount)"
        )
        print("preferencesRoot=\(output.preferencesRootPath)")
        if let previousProfileVersion = snapshot.previousProfileVersion {
            print("previousProfileVersion=\(previousProfileVersion)")
        }
        if let note = snapshot.note, !note.isEmpty {
            print("note=\(note)")
        }

        for summary in output.moduleSummaries {
            print(
                "  \(summary.module.rawValue): directives=\(summary.directiveCount) " +
                "rules=\(summary.ruleIds.joined(separator: ","))"
            )
        }
    }
}

private enum PreferenceProfileCLIMode: String, Codable {
    case loadedLatest = "loaded_latest"
    case rebuiltEphemeral = "rebuilt_ephemeral"
    case rebuiltAndPersisted = "rebuilt_and_persisted"
}

private struct PreferenceProfileCLIOutput: Codable {
    let mode: PreferenceProfileCLIMode
    let preferencesRootPath: String
    let snapshot: PreferenceProfileSnapshot
    let moduleSummaries: [PreferenceProfileModuleSummary]
}

private struct PreferenceProfileCLIOptions {
    let preferencesRootPath: String
    let rebuild: Bool
    let persist: Bool
    let profileVersion: String?
    let timestamp: String
    let actor: String
    let note: String?
    let printJSON: Bool
    let showHelp: Bool

    var preferencesRootURL: URL {
        Self.resolve(path: preferencesRootPath)
    }

    static func parse(arguments: [String]) throws -> Self {
        var preferencesRootPath = "data/preferences"
        var rebuild = false
        var persist = false
        var profileVersion: String?
        var timestamp = currentTimestamp()
        var actor = "cli"
        var note: String?
        var printJSON = false
        var showHelp = false

        var index = 1
        while index < arguments.count {
            let token = arguments[index]

            switch token {
            case "--preferences-root":
                index += 1
                guard index < arguments.count else {
                    throw PreferenceProfileCLIError.missingValue("--preferences-root")
                }
                preferencesRootPath = arguments[index]
            case "--rebuild":
                rebuild = true
            case "--persist":
                persist = true
            case "--profile-version":
                index += 1
                guard index < arguments.count else {
                    throw PreferenceProfileCLIError.missingValue("--profile-version")
                }
                profileVersion = arguments[index]
            case "--timestamp":
                index += 1
                guard index < arguments.count else {
                    throw PreferenceProfileCLIError.missingValue("--timestamp")
                }
                timestamp = arguments[index]
            case "--actor":
                index += 1
                guard index < arguments.count else {
                    throw PreferenceProfileCLIError.missingValue("--actor")
                }
                actor = arguments[index]
            case "--note":
                index += 1
                guard index < arguments.count else {
                    throw PreferenceProfileCLIError.missingValue("--note")
                }
                note = arguments[index]
            case "--json":
                printJSON = true
            case "--help", "-h":
                showHelp = true
            default:
                throw PreferenceProfileCLIError.unknownFlag(token)
            }

            index += 1
        }

        if !showHelp {
            guard isValidISO8601(timestamp) else {
                throw PreferenceProfileCLIError.invalidValue("--timestamp", timestamp)
            }
            if let profileVersion, profileVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw PreferenceProfileCLIError.invalidValue("--profile-version", profileVersion)
            }
            if actor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw PreferenceProfileCLIError.invalidValue("--actor", actor)
            }
        }

        return Self(
            preferencesRootPath: preferencesRootPath,
            rebuild: rebuild,
            persist: persist,
            profileVersion: profileVersion,
            timestamp: timestamp,
            actor: actor,
            note: note,
            printJSON: printJSON,
            showHelp: showHelp
        )
    }

    private static func currentTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func isValidISO8601(_ value: String) -> Bool {
        let primary = ISO8601DateFormatter()
        primary.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if primary.date(from: value) != nil {
            return true
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value) != nil
    }

    private static func resolve(path: String) -> URL {
        let url = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        return url.standardizedFileURL
    }
}

private enum PreferenceProfileCLIError: LocalizedError {
    case missingValue(String)
    case invalidValue(String, String)
    case unknownFlag(String)
    case persistRequiresRebuild
    case noProfileSnapshotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .invalidValue(let flag, let value):
            return "Invalid value for \(flag): \(value)"
        case .unknownFlag(let flag):
            return "Unknown flag: \(flag)"
        case .persistRequiresRebuild:
            return "--persist requires --rebuild."
        case .noProfileSnapshotFound(let rootPath):
            return "No latest profile snapshot found under \(rootPath). Re-run with --rebuild."
        }
    }
}
