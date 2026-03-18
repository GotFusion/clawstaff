import Foundation
import XCTest
@testable import OpenStaffApp

final class NextStateEvidenceBuilderTests: XCTestCase {
    func testBuilderDerivesDirectiveFailureBucketAndSeverity() {
        let input = NextStateEvidenceBuildInput(
            turnContext: NextStateEvidenceTurnContext(
                turnId: "turn-student-skillExecution-task-001-step-001",
                traceId: "trace-001",
                sessionId: "session-001",
                taskId: "task-001",
                stepId: "step-001"
            ),
            source: .teacherReview,
            summary: "Teacher requested a locator repair for the failed GUI step.",
            rawRefs: [
                NextStateEvidenceRawReference(
                    artifactKind: "teacherFeedback",
                    path: "data/feedback/2026-03-18/session-001-task-001-teacher-feedback.jsonl",
                    lineNumber: 3,
                    identifier: "feedback-001"
                )
            ],
            timestamp: "2026-03-18T10:00:00Z",
            directiveCandidate: NextStateDirectiveCandidate(
                action: "repair_locator",
                hint: "Button title changed from Save to Submit.",
                repairActionType: "updateSkillLocator"
            ),
            decisionHint: TeacherQuickFeedbackAction.fixLocator.rawValue
        )

        let evidence = NextStateEvidenceBuilder.build(input)

        XCTAssertEqual(evidence.source, .teacherReview)
        XCTAssertEqual(evidence.role, .directive)
        XCTAssertEqual(evidence.guiFailureBucket, .locatorResolutionFailed)
        XCTAssertEqual(evidence.severity, .error)
        XCTAssertEqual(evidence.confidence, 1.0)
        XCTAssertEqual(evidence.directiveCandidate?.repairActionType, "updateSkillLocator")
    }

    func testBuilderElevatesBlockedRuntimeToCritical() {
        let input = NextStateEvidenceBuildInput(
            turnContext: NextStateEvidenceTurnContext(
                turnId: "turn-student-skillExecution-task-002-step-001",
                sessionId: "session-002",
                taskId: "task-002",
                stepId: "step-001"
            ),
            source: .executionRuntime,
            summary: "Execution was blocked by a safety rule.",
            rawRefs: [
                NextStateEvidenceRawReference(
                    artifactKind: "executionLog",
                    path: "data/logs/2026-03-18/session-002-student.log",
                    lineNumber: 8
                )
            ],
            timestamp: "2026-03-18T10:05:00Z",
            evaluativeCandidate: NextStateEvaluativeCandidate(
                decision: "blocked",
                polarity: .negative,
                rationale: "Blocked by safety keyword."
            ),
            statusHint: "blocked",
            errorCodeHint: "EXE-ACTION-BLOCKED"
        )

        let evidence = NextStateEvidenceBuilder.build(input)

        XCTAssertEqual(evidence.role, .evaluative)
        XCTAssertEqual(evidence.guiFailureBucket, .riskBlocked)
        XCTAssertEqual(evidence.severity, .critical)
        XCTAssertEqual(evidence.confidence, 0.9)
    }

    func testAppendPersistsJSONLUnderEvidenceDirectory() throws {
        let fileManager = FileManager.default
        let workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("openstaff-next-state-evidence-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceRoot) }

        let evidenceRoot = workspaceRoot.appendingPathComponent("data/learning/evidence", isDirectory: true)
        let evidence = NextStateEvidenceBuilder.build(
            NextStateEvidenceBuildInput(
                turnContext: NextStateEvidenceTurnContext(
                    turnId: "turn-teaching-taskProgression-task-003-step-002",
                    traceId: "trace-003",
                    sessionId: "session-003",
                    taskId: "task-003",
                    stepId: "step-002"
                ),
                source: .benchmarkResult,
                summary: "Benchmark review approved this step.",
                rawRefs: [
                    NextStateEvidenceRawReference(
                        artifactKind: "benchmarkReview",
                        path: "data/benchmarks/generated/review-result.json"
                    )
                ],
                timestamp: "2026-03-18T10:10:00Z",
                evaluativeCandidate: NextStateEvaluativeCandidate(
                    decision: "approved",
                    polarity: .positive
                )
            )
        )

        let fileURL = try NextStateEvidenceBuilder.append(
            evidence,
            evidenceRootDirectory: evidenceRoot,
            fileManager: fileManager
        )

        XCTAssertTrue(fileManager.fileExists(atPath: fileURL.path))
        XCTAssertTrue(fileURL.path.hasSuffix("/2026-03-18/session-003/turn-teaching-taskProgression-task-003-step-002.jsonl"))

        let rawLines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(rawLines.count, 1)

        let decoded = try JSONDecoder().decode(
            NextStateEvidence.self,
            from: XCTUnwrap(rawLines.first).data(using: .utf8)!
        )
        XCTAssertEqual(decoded.evidenceId, evidence.evidenceId)
        XCTAssertEqual(decoded.schemaVersion, "openstaff.learning.next-state-evidence.v0")
        XCTAssertEqual(decoded.summary, "Benchmark review approved this step.")
    }
}
