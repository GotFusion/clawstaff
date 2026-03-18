import Foundation
import XCTest
@testable import OpenStaffApp

final class RuleBasedPreferenceSignalExtractorTests: XCTestCase {
    func testExtractorDistinguishesTeacherOutcomeRepairProcedureStyleAndRiskSignals() throws {
        let turn = makeTurn(mode: .assist, turnKind: .taskProgression)
        let rejected = makeEvidence(
            evidenceId: "evidence-teacher-rejected",
            source: .teacherReview,
            summary: "Teacher rejected the result.",
            timestamp: "2026-03-18T09:40:00Z",
            evaluativeCandidate: NextStateEvaluativeCandidate(
                decision: TeacherQuickFeedbackAction.rejected.rawValue,
                polarity: .negative,
                rationale: "Result did not match the expected output."
            )
        )
        let fixLocator = makeEvidence(
            evidenceId: "evidence-teacher-fix-locator",
            source: .teacherReview,
            summary: "Teacher requested a locator fix.",
            timestamp: "2026-03-18T09:40:10Z",
            guiFailureBucket: .locatorResolutionFailed,
            directiveCandidate: NextStateDirectiveCandidate(
                action: "repair_locator",
                hint: "Update the stale button title from Save to Submit.",
                repairActionType: "updateSkillLocator"
            )
        )
        let wrongOrder = makeEvidence(
            evidenceId: "evidence-teacher-wrong-order",
            source: .teacherReview,
            summary: "Teacher marked the order as wrong.",
            timestamp: "2026-03-18T09:40:20Z",
            evaluativeCandidate: NextStateEvaluativeCandidate(
                decision: TeacherQuickFeedbackAction.wrongOrder.rawValue,
                polarity: .negative,
                rationale: "You should search first and then open the result."
            )
        )
        let wrongStyle = makeEvidence(
            evidenceId: "evidence-teacher-wrong-style",
            source: .teacherReview,
            summary: "Teacher marked the style as wrong.",
            timestamp: "2026-03-18T09:40:30Z",
            evaluativeCandidate: NextStateEvaluativeCandidate(
                decision: TeacherQuickFeedbackAction.wrongStyle.rawValue,
                polarity: .negative,
                rationale: "Keep the response concise and direct."
            )
        )
        let tooDangerous = makeEvidence(
            evidenceId: "evidence-teacher-dangerous",
            source: .teacherReview,
            summary: "Teacher marked this as too dangerous.",
            timestamp: "2026-03-18T09:40:40Z",
            guiFailureBucket: .riskBlocked,
            evaluativeCandidate: NextStateEvaluativeCandidate(
                decision: TeacherQuickFeedbackAction.tooDangerous.rawValue,
                polarity: .negative,
                rationale: "This should never auto-run."
            )
        )

        let signals = RuleBasedPreferenceSignalExtractor.extract(
            turn: turn,
            evidence: [rejected, fixLocator, wrongOrder, wrongStyle, tooDangerous],
            taskFamily: "browser.navigation"
        )

        XCTAssertEqual(signals.count, 5)

        let outcome = try XCTUnwrap(signals.first(where: { $0.type == .outcome }))
        XCTAssertEqual(outcome.evaluativeDecision, .fail)
        XCTAssertEqual(outcome.polarity, .discourage)
        XCTAssertEqual(outcome.scope.level, .taskFamily)
        XCTAssertEqual(outcome.scope.taskFamily, "browser.navigation")

        let repair = try XCTUnwrap(signals.first(where: { $0.type == .repair }))
        XCTAssertEqual(repair.scope.level, .taskFamily)
        XCTAssertEqual(repair.proposedAction, "updateSkillLocator")
        XCTAssertTrue(repair.hasDirectivePayload)

        let procedure = try XCTUnwrap(signals.first(where: { $0.type == .procedure }))
        XCTAssertEqual(procedure.scope.level, .taskFamily)
        XCTAssertEqual(procedure.evaluativeDecision, .fail)

        let style = try XCTUnwrap(signals.first(where: { $0.type == .style }))
        XCTAssertEqual(style.scope.level, .global)
        XCTAssertEqual(style.polarity, .discourage)

        let risk = try XCTUnwrap(signals.first(where: { $0.type == .risk }))
        XCTAssertEqual(risk.scope.level, .app)
        XCTAssertEqual(risk.proposedAction, "require_teacher_confirmation")
        XCTAssertTrue(risk.hasDirectivePayload)
    }

    func testExtractorBuildsReplayDriftBenchmarkAndSafetySignals() throws {
        let turn = makeTurn(mode: .student, turnKind: .skillExecution)
        let replayVerify = makeEvidence(
            evidenceId: "evidence-replay-001",
            source: .replayVerify,
            summary: "Replay verification degraded because the locator fell back to coordinates.",
            timestamp: "2026-03-18T10:00:00Z",
            guiFailureBucket: .locatorResolutionFailed,
            evaluativeCandidate: NextStateEvaluativeCandidate(
                decision: "degraded",
                polarity: .negative,
                rationale: "Replay only found coordinate fallback."
            ),
            directiveCandidate: NextStateDirectiveCandidate(
                action: "repair_locator",
                hint: "Refresh semantic target candidates before the next run.",
                repairActionType: "relocalize"
            )
        )
        let driftDetection = makeEvidence(
            evidenceId: "evidence-drift-001",
            source: .driftDetection,
            summary: "Drift detector found UI text changed from Save to Submit on the target button.",
            timestamp: "2026-03-18T10:01:00Z",
            guiFailureBucket: .locatorResolutionFailed,
            evaluativeCandidate: NextStateEvaluativeCandidate(
                decision: "driftDetected",
                polarity: .negative,
                rationale: "UI text anchor changed."
            ),
            directiveCandidate: NextStateDirectiveCandidate(
                action: "refresh_skill_locator",
                hint: "Update the saved title/text anchor from Save to Submit.",
                repairActionType: "updateSkillLocator"
            )
        )
        let benchmark = makeEvidence(
            evidenceId: "evidence-benchmark-001",
            source: .benchmarkResult,
            summary: "skill preflight=needs_teacher_confirmation; runtime=succeeded; expectedRuntime=succeeded",
            timestamp: "2026-03-18T10:02:00Z",
            evaluativeCandidate: NextStateEvaluativeCandidate(
                decision: "approved",
                polarity: .positive,
                rationale: "Benchmark runner preserved teacher confirmation for this high-risk step."
            )
        )
        let blockedRuntime = makeEvidence(
            evidenceId: "evidence-runtime-blocked-001",
            source: .executionRuntime,
            summary: "Execution was blocked by a safety rule.",
            timestamp: "2026-03-18T10:03:00Z",
            guiFailureBucket: .riskBlocked,
            evaluativeCandidate: NextStateEvaluativeCandidate(
                decision: "blocked",
                polarity: .negative,
                rationale: "Blocked by safety keyword."
            )
        )

        let signals = RuleBasedPreferenceSignalExtractor.extract(
            turn: turn,
            evidence: [replayVerify, driftDetection, benchmark, blockedRuntime],
            taskFamily: "student.execution"
        )

        XCTAssertEqual(signals.filter { $0.type == .locator }.count, 2)
        XCTAssertEqual(signals.filter { $0.type == .repair }.count, 1)
        XCTAssertEqual(signals.filter { $0.type == .outcome }.count, 1)
        XCTAssertEqual(signals.filter { $0.type == .risk }.count, 2)

        let replayLocator = try XCTUnwrap(
            signals.first(where: { $0.signalId == "signal-locator-evidence-replay-001" })
        )
        XCTAssertEqual(replayLocator.scope.level, .app)
        XCTAssertEqual(replayLocator.proposedAction, "relocalize")

        let driftRepair = try XCTUnwrap(
            signals.first(where: { $0.signalId == "signal-repair-evidence-drift-001" })
        )
        XCTAssertEqual(driftRepair.scope.level, .taskFamily)
        XCTAssertEqual(driftRepair.proposedAction, "updateSkillLocator")

        let benchmarkOutcome = try XCTUnwrap(signals.first(where: {
            $0.signalId == "signal-outcome-evidence-benchmark-001"
        }))
        XCTAssertEqual(benchmarkOutcome.evaluativeDecision, .pass)
        XCTAssertEqual(benchmarkOutcome.polarity, .reinforce)

        let benchmarkRisk = try XCTUnwrap(signals.first(where: {
            $0.signalId == "signal-risk-evidence-benchmark-001"
        }))
        XCTAssertEqual(benchmarkRisk.evaluativeDecision, .pass)
        XCTAssertEqual(benchmarkRisk.proposedAction, "require_teacher_confirmation")

        let runtimeRisk = try XCTUnwrap(signals.first(where: {
            $0.signalId == "signal-risk-evidence-runtime-blocked-001"
        }))
        XCTAssertEqual(runtimeRisk.evaluativeDecision, .fail)
        XCTAssertEqual(runtimeRisk.polarity, .discourage)
        XCTAssertEqual(runtimeRisk.scope.level, .app)
    }

    func testWritePersistsSignalsUnderPreferencesDirectory() throws {
        let fileManager = FileManager.default
        let workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("openstaff-preference-signals-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceRoot) }

        let signalsRoot = workspaceRoot.appendingPathComponent("data/preferences/signals", isDirectory: true)
        let turn = makeTurn(mode: .assist, turnKind: .taskProgression)
        let rejected = makeEvidence(
            evidenceId: "evidence-write-outcome",
            source: .teacherReview,
            summary: "Teacher rejected the result.",
            timestamp: "2026-03-18T11:00:00Z",
            evaluativeCandidate: NextStateEvaluativeCandidate(
                decision: TeacherQuickFeedbackAction.rejected.rawValue,
                polarity: .negative
            )
        )
        let fixLocator = makeEvidence(
            evidenceId: "evidence-write-repair",
            source: .teacherReview,
            summary: "Teacher requested a locator fix.",
            timestamp: "2026-03-18T11:00:10Z",
            guiFailureBucket: .locatorResolutionFailed,
            directiveCandidate: NextStateDirectiveCandidate(
                action: "repair_locator",
                hint: "Update the locator.",
                repairActionType: "updateSkillLocator"
            )
        )

        let signals = RuleBasedPreferenceSignalExtractor.extract(
            turn: turn,
            evidence: [rejected, fixLocator],
            taskFamily: "browser.navigation"
        )
        let urls = try RuleBasedPreferenceSignalExtractor.write(
            signals,
            signalsRootDirectory: signalsRoot,
            fileManager: fileManager
        )

        XCTAssertEqual(urls.count, 1)
        let fileURL = try XCTUnwrap(urls.first)
        XCTAssertTrue(fileManager.fileExists(atPath: fileURL.path))
        XCTAssertTrue(fileURL.path.hasSuffix("/2026-03-18/session-001/\(turn.turnId).json"))

        let decoded = try JSONDecoder().decode(
            [PreferenceSignal].self,
            from: Data(contentsOf: fileURL)
        )
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded.map(\.type), [.outcome, .repair])
    }

    func testHistoricalCoverageExtractsSignalsForAtLeastSixtyPercentOfThirtyReviewBackedSamples() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let evidenceRoot = repoRoot.appendingPathComponent("data/learning/evidence", isDirectory: true)
        let evidenceURLs = try historicalEvidenceURLs(root: evidenceRoot)

        XCTAssertGreaterThanOrEqual(evidenceURLs.count, 30)

        var withSignals = 0
        for url in evidenceURLs.prefix(30) {
            let evidence = try readEvidenceRows(at: url)
            guard let seed = evidence.first else {
                continue
            }

            let turn = makeHistoricalTurn(from: seed)
            let signals = RuleBasedPreferenceSignalExtractor.extract(turn: turn, evidence: evidence)
            if !signals.isEmpty {
                withSignals += 1
            }
        }

        XCTAssertGreaterThanOrEqual(withSignals, 18)
    }

    private func makeTurn(
        mode: OpenStaffMode,
        turnKind: InteractionTurnKind
    ) -> InteractionTurn {
        InteractionTurn(
            turnId: "turn-\(mode.rawValue)-\(turnKind.rawValue)-task-001-step-001",
            traceId: "trace-learning-\(mode.rawValue)-task-001-step-001",
            sessionId: "session-001",
            taskId: "task-001",
            stepId: "step-001",
            mode: mode,
            turnKind: turnKind,
            stepIndex: 1,
            intentSummary: "在 Safari 中点击目标按钮。",
            actionSummary: "点击 Save 按钮。",
            actionKind: .guiAction,
            status: .failed,
            learningState: .reviewed,
            privacyTags: [],
            riskLevel: .medium,
            appContext: InteractionTurnAppContext(
                appName: "Safari",
                appBundleId: "com.apple.Safari",
                windowTitle: "OpenStaff"
            ),
            observationRef: InteractionTurnObservationReference(
                rawEventLogPath: "data/raw-events/2026-03-18/session-001.jsonl",
                taskChunkPath: "data/task-chunks/2026-03-18/task-001.json",
                eventIds: ["evt-001"],
                appContext: InteractionTurnAppContext(
                    appName: "Safari",
                    appBundleId: "com.apple.Safari",
                    windowTitle: "OpenStaff"
                )
            ),
            semanticTargetSetRef: nil,
            stepReference: InteractionTurnStepReference(
                stepId: "step-001",
                stepIndex: 1,
                instruction: "点击 Save 按钮。",
                sourceEventIds: ["evt-001"]
            ),
            execution: nil,
            review: nil,
            sourceRefs: [
                InteractionTurnSourceReference(
                    artifactKind: "knowledgeItem",
                    path: "data/knowledge/2026-03-18/task-001.json",
                    identifier: "ki-task-001"
                )
            ],
            startedAt: "2026-03-18T09:39:59Z",
            endedAt: "2026-03-18T10:04:00Z"
        )
    }

    private func makeEvidence(
        evidenceId: String,
        source: NextStateEvidenceSource,
        summary: String,
        timestamp: String,
        guiFailureBucket: NextStateEvidenceGUIFailureBucket? = nil,
        evaluativeCandidate: NextStateEvaluativeCandidate? = nil,
        directiveCandidate: NextStateDirectiveCandidate? = nil
    ) -> NextStateEvidence {
        NextStateEvidence(
            evidenceId: evidenceId,
            turnId: "turn-assist-taskProgression-task-001-step-001",
            traceId: "trace-learning-assist-task-001-step-001",
            sessionId: "session-001",
            taskId: "task-001",
            stepId: "step-001",
            source: source,
            summary: summary,
            rawRefs: [
                NextStateEvidenceRawReference(
                    artifactKind: "sample",
                    path: "data/sample.json"
                )
            ],
            timestamp: timestamp,
            confidence: 0.9,
            severity: .warning,
            role: directiveCandidate != nil && evaluativeCandidate != nil ? .mixed : (directiveCandidate != nil ? .directive : .evaluative),
            guiFailureBucket: guiFailureBucket,
            evaluativeCandidate: evaluativeCandidate,
            directiveCandidate: directiveCandidate
        )
    }

    private func makeHistoricalTurn(from evidence: NextStateEvidence) -> InteractionTurn {
        InteractionTurn(
            turnId: evidence.turnId,
            traceId: evidence.traceId ?? "trace-historical-\(evidence.turnId)",
            sessionId: evidence.sessionId,
            taskId: evidence.taskId,
            stepId: evidence.stepId,
            mode: .student,
            turnKind: .skillExecution,
            stepIndex: 1,
            intentSummary: "Historical benchmark-backed learning sample.",
            actionSummary: "Replay historical learning sample.",
            actionKind: .guiAction,
            status: .succeeded,
            learningState: .reviewed,
            privacyTags: [],
            riskLevel: .medium,
            appContext: InteractionTurnAppContext(
                appName: "Xcode",
                appBundleId: "com.apple.dt.Xcode",
                windowTitle: "Historical Sample"
            ),
            observationRef: InteractionTurnObservationReference(
                rawEventLogPath: nil,
                taskChunkPath: nil,
                eventIds: [],
                appContext: InteractionTurnAppContext(
                    appName: "Xcode",
                    appBundleId: "com.apple.dt.Xcode",
                    windowTitle: "Historical Sample"
                )
            ),
            semanticTargetSetRef: nil,
            stepReference: InteractionTurnStepReference(
                stepId: evidence.stepId,
                stepIndex: 1,
                instruction: "Replay historical learning sample.",
                sourceEventIds: []
            ),
            execution: nil,
            review: nil,
            sourceRefs: [],
            startedAt: evidence.timestamp,
            endedAt: evidence.timestamp
        )
    }

    private func historicalEvidenceURLs(root: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        )
        var urls: [URL] = []
        while let candidate = enumerator?.nextObject() as? URL {
            if candidate.pathExtension == "jsonl" {
                let evidence = try readEvidenceRows(at: candidate)
                if evidence.contains(where: { row in
                    row.source == .benchmarkResult
                        || row.source == .teacherReview
                        || row.source == .replayVerify
                        || row.source == .driftDetection
                        || (row.source == .executionRuntime && row.guiFailureBucket == .riskBlocked)
                }) {
                    urls.append(candidate)
                }
            }
        }
        return urls.sorted(by: { $0.path < $1.path })
    }

    private func readEvidenceRows(at url: URL) throws -> [NextStateEvidence] {
        let decoder = JSONDecoder()
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
            .map { line in
                try decoder.decode(NextStateEvidence.self, from: Data(line.utf8))
            }
    }
}
