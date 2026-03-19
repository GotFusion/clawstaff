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
            let rollbackService = PreferenceRollbackService(profileBuilder: builder)
            let driftMonitor = PreferenceDriftMonitor()

            let output = try run(
                options: options,
                store: store,
                builder: builder,
                rollbackService: rollbackService,
                driftMonitor: driftMonitor
            )

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

    fileprivate static func run(
        options: PreferenceProfileCLIOptions,
        store: PreferenceMemoryStore,
        builder: PreferenceProfileBuilder,
        rollbackService: PreferenceRollbackService,
        driftMonitor: PreferenceDriftMonitor
    ) throws -> PreferenceProfileCLIOutput {
        switch options.command {
        case .loadLatest:
            guard let snapshot = try store.loadLatestProfileSnapshot() else {
                throw PreferenceProfileCLIError.noProfileSnapshotFound(options.preferencesRootURL.path)
            }
            return PreferenceProfileCLIOutput(
                mode: .loadedLatest,
                preferencesRootPath: options.preferencesRootURL.path,
                snapshot: snapshot,
                moduleSummaries: builder.summaries(for: snapshot.profile)
            )
        case .rebuild:
            switch options.persist {
            case false:
                let result = try builder.rebuild(
                    using: store,
                    profileVersion: options.profileVersion,
                    generatedAt: options.timestamp,
                    note: options.annotation
                )
                return PreferenceProfileCLIOutput(
                    mode: .rebuiltEphemeral,
                    preferencesRootPath: options.preferencesRootURL.path,
                    snapshot: result.snapshot,
                    moduleSummaries: result.moduleSummaries
                )
            case true:
                let result = try builder.rebuildAndStore(
                    using: store,
                    actor: options.actor,
                    profileVersion: options.profileVersion,
                    generatedAt: options.timestamp,
                    note: options.annotation
                )
                return PreferenceProfileCLIOutput(
                    mode: .rebuiltAndPersisted,
                    preferencesRootPath: options.preferencesRootURL.path,
                    snapshot: result.snapshot,
                    moduleSummaries: result.moduleSummaries
                )
            }
        case .audit:
            let entries = try store.loadAuditEntries(
                matching: PreferenceAuditLogQuery(
                    date: options.auditDate,
                    ruleId: options.auditRuleId,
                    profileVersion: options.auditProfileVersion
                )
            )
            return PreferenceProfileCLIOutput(
                mode: .auditLoaded,
                preferencesRootPath: options.preferencesRootURL.path,
                auditEntries: entries
            )
        case .driftMonitor:
            let report = try driftMonitor.analyze(
                using: store,
                profileVersion: options.driftProfileVersion,
                generatedAt: options.timestamp
            )
            let snapshot: PreferenceProfileSnapshot?
            if let driftProfileVersion = options.driftProfileVersion {
                snapshot = try store.loadProfileSnapshot(profileVersion: driftProfileVersion)
            } else {
                snapshot = try store.loadLatestProfileSnapshot()
            }
            return PreferenceProfileCLIOutput(
                mode: .driftMonitorLoaded,
                preferencesRootPath: options.preferencesRootURL.path,
                snapshot: snapshot,
                moduleSummaries: snapshot.map { builder.summaries(for: $0.profile) },
                driftReport: report
            )
        case .rollbackRule:
            guard let ruleId = options.rollbackRuleId else {
                throw PreferenceProfileCLIError.invalidRollbackConfiguration
            }
            if options.shouldApplyMutation {
                let result = try rollbackService.applyRuleRevocation(
                    ruleId: ruleId,
                    using: store,
                    actor: options.actor,
                    timestamp: options.timestamp,
                    reason: options.annotation,
                    profileVersion: options.profileVersion
                )
                return PreferenceProfileCLIOutput(
                    mode: .rollbackApplied,
                    preferencesRootPath: options.preferencesRootURL.path,
                    snapshot: result.snapshot,
                    moduleSummaries: result.plan.moduleSummaries,
                    rollbackPlan: result.plan,
                    rollbackResult: result
                )
            }

            let plan = try rollbackService.previewRuleRevocation(
                ruleId: ruleId,
                using: store,
                actor: options.actor,
                timestamp: options.timestamp,
                reason: options.annotation,
                projectedProfileVersion: options.profileVersion
            )
            return PreferenceProfileCLIOutput(
                mode: .rollbackPreview,
                preferencesRootPath: options.preferencesRootURL.path,
                snapshot: plan.projectedSnapshot,
                moduleSummaries: plan.moduleSummaries,
                rollbackPlan: plan
            )
        case .rollbackProfile:
            guard let rollbackProfileVersion = options.rollbackProfileVersion else {
                throw PreferenceProfileCLIError.invalidRollbackConfiguration
            }
            if options.shouldApplyMutation {
                let result = try rollbackService.applyProfileRollback(
                    to: rollbackProfileVersion,
                    using: store,
                    actor: options.actor,
                    timestamp: options.timestamp,
                    reason: options.annotation,
                    profileVersion: options.profileVersion
                )
                return PreferenceProfileCLIOutput(
                    mode: .rollbackApplied,
                    preferencesRootPath: options.preferencesRootURL.path,
                    snapshot: result.snapshot,
                    moduleSummaries: result.plan.moduleSummaries,
                    rollbackPlan: result.plan,
                    rollbackResult: result
                )
            }

            let plan = try rollbackService.previewProfileRollback(
                to: rollbackProfileVersion,
                using: store,
                actor: options.actor,
                timestamp: options.timestamp,
                reason: options.annotation,
                projectedProfileVersion: options.profileVersion
            )
            return PreferenceProfileCLIOutput(
                mode: .rollbackPreview,
                preferencesRootPath: options.preferencesRootURL.path,
                snapshot: plan.projectedSnapshot,
                moduleSummaries: plan.moduleSummaries,
                rollbackPlan: plan
            )
        }
    }

    static func printHelp() {
        print("""
        OpenStaffPreferenceProfileCLI

        Usage:
          make preference-profile ARGS="--preferences-root data/preferences --json"
          make preference-profile ARGS="--preferences-root data/preferences --rebuild --persist --json"
          make preference-profile ARGS="--preferences-root data/preferences --audit --audit-rule-id rule-123 --json"
          make preference-profile ARGS="--preferences-root data/preferences --drift-monitor --json"
          make preference-profile ARGS="--preferences-root data/preferences --rollback-profile-version profile-2026-03-19-001 --dry-run --json"
          make preference-profile ARGS="--preferences-root data/preferences --rollback-rule rule-123 --persist --json"

        Flags:
          --preferences-root <path>        Preference store root. Default: data/preferences
          --rebuild                        Rebuild a profile snapshot from currently active rules.
          --persist                        Persist rebuild / rollback results.
          --profile-version <id>           Optional explicit output profile version.
          --timestamp <iso8601>            Operation timestamp. Default: now.
          --actor <id>                     Audit actor. Default: cli
          --note <text>                    Optional note for rebuilds or rollback history.
          --reason <text>                  Alias of --note for rollback operations.
          --audit                          Load preference audit entries instead of profile snapshots.
          --audit-date <yyyy-mm-dd>        Restrict audit log loading to a single date file.
          --audit-rule-id <id>             Filter audit entries by rule id.
          --audit-profile-version <id>     Filter audit entries by profile version.
          --drift-monitor                  Run preference drift monitoring on the latest profile snapshot.
          --drift-profile-version <id>     Optional explicit profile snapshot version for drift monitoring.
          --rollback-rule <id>             Preview or revoke a single rule.
          --rollback-profile-version <id>  Preview or rollback to a stored profile snapshot.
          --dry-run                        Force rollback modes to preview without writing.
          --json                           Print structured JSON output.
          --help                           Show this help message.
        """)
    }

    fileprivate static func printSummary(_ output: PreferenceProfileCLIOutput) {
        print("preferencesRoot=\(output.preferencesRootPath)")

        if let rollbackPlan = output.rollbackPlan {
            print(
                "rollback \(output.mode.rawValue). " +
                "operation=\(rollbackPlan.operation.rawValue) " +
                "projectedProfileVersion=\(rollbackPlan.projectedSnapshot.profileVersion) " +
                "impactedRules=\(rollbackPlan.impactedRuleIds.count) " +
                "missingRules=\(rollbackPlan.missingRuleIds.count)"
            )
            if let currentProfileVersion = rollbackPlan.currentProfileVersion {
                print("currentProfileVersion=\(currentProfileVersion)")
            }
            if let targetProfileVersion = rollbackPlan.targetProfileVersion {
                print("targetProfileVersion=\(targetProfileVersion)")
            }
            if let ruleId = rollbackPlan.ruleId {
                print("ruleId=\(ruleId)")
            }
            print("reason=\(rollbackPlan.reason)")
            for impact in rollbackPlan.ruleImpacts {
                print(
                    "  impact rule=\(impact.ruleId) " +
                    "status=\(impact.previousActivationStatus.rawValue)->\(impact.newActivationStatus.rawValue)"
                )
            }
            if !rollbackPlan.missingRuleIds.isEmpty {
                print("missingRuleIds=\(rollbackPlan.missingRuleIds.joined(separator: ","))")
            }
        }

        if let auditEntries = output.auditEntries {
            print("audit entries loaded. count=\(auditEntries.count)")
            for entry in auditEntries {
                let ruleFragment = entry.ruleId.map { " rule=\($0)" } ?? ""
                let profileFragment = entry.profileVersion.map { " profile=\($0)" } ?? ""
                print(
                    "  \(entry.timestamp) action=\(entry.action.rawValue) " +
                    "actor=\(entry.actor) source=\(entry.source.kind.rawValue)\(ruleFragment)\(profileFragment)"
                )
            }
        }

        if let driftReport = output.driftReport {
            print(
                "drift monitor loaded. " +
                "profileVersion=\(driftReport.profileVersion ?? "__none__") " +
                "activeRules=\(driftReport.activeRuleIds.count) " +
                "findings=\(driftReport.findings.count) " +
                "assemblyDecisions=\(driftReport.dataAvailability.totalAssemblyDecisionCount)"
            )
            if !driftReport.dataAvailability.usageMetricsEvaluated {
                print("usageMetricsEvaluated=false")
            }
            for finding in driftReport.findings {
                print(
                    "  \(finding.severity.rawValue) " +
                    "rule=\(finding.ruleId) " +
                    "kind=\(finding.kind.rawValue) " +
                    "summary=\(finding.summary)"
                )
            }
        }

        if let snapshot = output.snapshot {
            print(
                "profile \(output.mode.rawValue). " +
                "profileVersion=\(snapshot.profileVersion) " +
                "activeRules=\(snapshot.profile.activeRuleIds.count) " +
                "directives=\(snapshot.profile.totalDirectiveCount)"
            )
            if let previousProfileVersion = snapshot.previousProfileVersion {
                print("previousProfileVersion=\(previousProfileVersion)")
            }
            if let note = snapshot.note, !note.isEmpty {
                print("note=\(note)")
            }

            for summary in output.moduleSummaries ?? [] {
                print(
                    "  \(summary.module.rawValue): directives=\(summary.directiveCount) " +
                    "rules=\(summary.ruleIds.joined(separator: ","))"
                )
            }
        }
    }
}

private enum PreferenceProfileCLIMode: String, Codable {
    case loadedLatest = "loaded_latest"
    case rebuiltEphemeral = "rebuilt_ephemeral"
    case rebuiltAndPersisted = "rebuilt_and_persisted"
    case auditLoaded = "audit_loaded"
    case driftMonitorLoaded = "drift_monitor_loaded"
    case rollbackPreview = "rollback_preview"
    case rollbackApplied = "rollback_applied"
}

private struct PreferenceProfileCLIOutput: Codable {
    let mode: PreferenceProfileCLIMode
    let preferencesRootPath: String
    let snapshot: PreferenceProfileSnapshot?
    let moduleSummaries: [PreferenceProfileModuleSummary]?
    let auditEntries: [PreferenceAuditLogEntry]?
    let driftReport: PreferenceDriftMonitorReport?
    let rollbackPlan: PreferenceRollbackPlan?
    let rollbackResult: PreferenceRollbackResult?

    init(
        mode: PreferenceProfileCLIMode,
        preferencesRootPath: String,
        snapshot: PreferenceProfileSnapshot? = nil,
        moduleSummaries: [PreferenceProfileModuleSummary]? = nil,
        auditEntries: [PreferenceAuditLogEntry]? = nil,
        driftReport: PreferenceDriftMonitorReport? = nil,
        rollbackPlan: PreferenceRollbackPlan? = nil,
        rollbackResult: PreferenceRollbackResult? = nil
    ) {
        self.mode = mode
        self.preferencesRootPath = preferencesRootPath
        self.snapshot = snapshot
        self.moduleSummaries = moduleSummaries
        self.auditEntries = auditEntries
        self.driftReport = driftReport
        self.rollbackPlan = rollbackPlan
        self.rollbackResult = rollbackResult
    }
}

private enum PreferenceProfileCLICommand {
    case loadLatest
    case rebuild
    case audit
    case driftMonitor
    case rollbackRule
    case rollbackProfile
}

private struct PreferenceProfileCLIOptions {
    let preferencesRootPath: String
    let rebuild: Bool
    let persist: Bool
    let profileVersion: String?
    let timestamp: String
    let actor: String
    let annotation: String?
    let audit: Bool
    let auditDate: String?
    let auditRuleId: String?
    let auditProfileVersion: String?
    let driftMonitor: Bool
    let driftProfileVersion: String?
    let rollbackRuleId: String?
    let rollbackProfileVersion: String?
    let dryRun: Bool
    let printJSON: Bool
    let showHelp: Bool

    var preferencesRootURL: URL {
        Self.resolve(path: preferencesRootPath)
    }

    var command: PreferenceProfileCLICommand {
        if audit {
            return .audit
        }
        if driftMonitor {
            return .driftMonitor
        }
        if rollbackRuleId != nil {
            return .rollbackRule
        }
        if rollbackProfileVersion != nil {
            return .rollbackProfile
        }
        if rebuild {
            return .rebuild
        }
        return .loadLatest
    }

    var shouldApplyMutation: Bool {
        persist && !dryRun
    }

    static func parse(arguments: [String]) throws -> Self {
        var preferencesRootPath = "data/preferences"
        var rebuild = false
        var persist = false
        var profileVersion: String?
        var timestamp = currentTimestamp()
        var actor = "cli"
        var annotation: String?
        var audit = false
        var auditDate: String?
        var auditRuleId: String?
        var auditProfileVersion: String?
        var driftMonitor = false
        var driftProfileVersion: String?
        var rollbackRuleId: String?
        var rollbackProfileVersion: String?
        var dryRun = false
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
            case "--note", "--reason":
                index += 1
                guard index < arguments.count else {
                    throw PreferenceProfileCLIError.missingValue(token)
                }
                annotation = arguments[index]
            case "--audit":
                audit = true
            case "--audit-date":
                index += 1
                guard index < arguments.count else {
                    throw PreferenceProfileCLIError.missingValue("--audit-date")
                }
                auditDate = arguments[index]
            case "--audit-rule-id":
                index += 1
                guard index < arguments.count else {
                    throw PreferenceProfileCLIError.missingValue("--audit-rule-id")
                }
                auditRuleId = arguments[index]
            case "--audit-profile-version":
                index += 1
                guard index < arguments.count else {
                    throw PreferenceProfileCLIError.missingValue("--audit-profile-version")
                }
                auditProfileVersion = arguments[index]
            case "--drift-monitor":
                driftMonitor = true
            case "--drift-profile-version":
                index += 1
                guard index < arguments.count else {
                    throw PreferenceProfileCLIError.missingValue("--drift-profile-version")
                }
                driftProfileVersion = arguments[index]
            case "--rollback-rule":
                index += 1
                guard index < arguments.count else {
                    throw PreferenceProfileCLIError.missingValue("--rollback-rule")
                }
                rollbackRuleId = arguments[index]
            case "--rollback-profile-version":
                index += 1
                guard index < arguments.count else {
                    throw PreferenceProfileCLIError.missingValue("--rollback-profile-version")
                }
                rollbackProfileVersion = arguments[index]
            case "--dry-run":
                dryRun = true
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
            if let driftProfileVersion,
               driftProfileVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw PreferenceProfileCLIError.invalidValue("--drift-profile-version", driftProfileVersion)
            }
            if actor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw PreferenceProfileCLIError.invalidValue("--actor", actor)
            }
            if let auditDate, !isValidAuditDate(auditDate) {
                throw PreferenceProfileCLIError.invalidValue("--audit-date", auditDate)
            }

            let primaryCommands = [
                rebuild ? "--rebuild" : nil,
                audit ? "--audit" : nil,
                driftMonitor ? "--drift-monitor" : nil,
                rollbackRuleId != nil ? "--rollback-rule" : nil,
                rollbackProfileVersion != nil ? "--rollback-profile-version" : nil
            ].compactMap { $0 }

            if primaryCommands.count > 1 {
                throw PreferenceProfileCLIError.conflictingCommands(primaryCommands)
            }
            if driftProfileVersion != nil && !driftMonitor {
                throw PreferenceProfileCLIError.invalidValue(
                    "--drift-profile-version",
                    driftProfileVersion ?? ""
                )
            }
            if persist && (audit || driftMonitor) {
                throw PreferenceProfileCLIError.persistRequiresMutationCommand
            }
            if dryRun && (audit || driftMonitor || (rollbackRuleId == nil && rollbackProfileVersion == nil)) {
                throw PreferenceProfileCLIError.dryRunRequiresRollback
            }
            if persist && !rebuild && rollbackRuleId == nil && rollbackProfileVersion == nil {
                throw PreferenceProfileCLIError.persistRequiresMutationCommand
            }
        }

        return Self(
            preferencesRootPath: preferencesRootPath,
            rebuild: rebuild,
            persist: persist,
            profileVersion: profileVersion,
            timestamp: timestamp,
            actor: actor,
            annotation: annotation,
            audit: audit,
            auditDate: auditDate,
            auditRuleId: auditRuleId,
            auditProfileVersion: auditProfileVersion,
            driftMonitor: driftMonitor,
            driftProfileVersion: driftProfileVersion,
            rollbackRuleId: rollbackRuleId,
            rollbackProfileVersion: rollbackProfileVersion,
            dryRun: dryRun,
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

    private static func isValidAuditDate(_ value: String) -> Bool {
        value.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil
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
    case conflictingCommands([String])
    case persistRequiresMutationCommand
    case dryRunRequiresRollback
    case invalidRollbackConfiguration
    case noProfileSnapshotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .invalidValue(let flag, let value):
            return "Invalid value for \(flag): \(value)"
        case .unknownFlag(let flag):
            return "Unknown flag: \(flag)"
        case .conflictingCommands(let commands):
            return "Conflicting commands: \(commands.joined(separator: ", "))"
        case .persistRequiresMutationCommand:
            return "--persist requires --rebuild, --rollback-rule, or --rollback-profile-version."
        case .dryRunRequiresRollback:
            return "--dry-run is only supported with rollback commands."
        case .invalidRollbackConfiguration:
            return "Rollback command is missing its target identifier."
        case .noProfileSnapshotFound(let rootPath):
            return "No latest profile snapshot found under \(rootPath). Re-run with --rebuild."
        }
    }
}
