import Foundation
import XCTest
@testable import OpenStaffApp

final class PreferenceSignalContractsTests: XCTestCase {
    func testScopeLevelMarksV0DefaultActivation() {
        XCTAssertTrue(PreferenceSignalScope.global.isEnabledByDefaultInV0)
        XCTAssertTrue(PreferenceSignalScope.app.isEnabledByDefaultInV0)
        XCTAssertTrue(PreferenceSignalScope.taskFamily.isEnabledByDefaultInV0)
        XCTAssertFalse(PreferenceSignalScope.skillFamily.isEnabledByDefaultInV0)
        XCTAssertFalse(PreferenceSignalScope.windowPattern.isEnabledByDefaultInV0)
    }

    func testSignalRoundTripsDirectivePayload() throws {
        let signal = PreferenceSignal(
            signalId: "signal-locator-001",
            turnId: "turn-assist-taskProgression-task-001-step-001",
            traceId: "trace-learning-assist-task-001-step-001",
            sessionId: "session-001",
            taskId: "task-001",
            stepId: "step-001",
            type: .locator,
            evaluativeDecision: .fail,
            polarity: .discourage,
            scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
            hint: "Prefer AX role and text anchors before using coordinates.",
            confidence: 0.91,
            evidenceIds: ["evidence-001", "evidence-002"],
            proposedAction: "update_locator_priority",
            promotionStatus: .candidate,
            timestamp: "2026-03-18T09:45:00Z"
        )

        let data = try JSONEncoder().encode(signal)
        let decoded = try JSONDecoder().decode(PreferenceSignal.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, "openstaff.learning.preference-signal.v0")
        XCTAssertEqual(decoded.scope.level, .app)
        XCTAssertEqual(decoded.scope.appBundleId, "com.apple.Safari")
        XCTAssertTrue(decoded.hasDirectivePayload)
        XCTAssertTrue(decoded.isEnabledByDefaultInV0)
    }

    func testSignalSupportsEvaluativeOnlyPayload() {
        let signal = PreferenceSignal(
            signalId: "signal-outcome-001",
            turnId: "turn-student-skillExecution-task-002-step-001",
            sessionId: "session-002",
            taskId: "task-002",
            stepId: "step-001",
            type: .outcome,
            evaluativeDecision: .pass,
            polarity: .reinforce,
            scope: .global(),
            confidence: 0.87,
            evidenceIds: ["evidence-003"],
            promotionStatus: .candidate,
            timestamp: "2026-03-18T10:10:00Z"
        )

        XCTAssertNil(signal.hint)
        XCTAssertNil(signal.proposedAction)
        XCTAssertFalse(signal.hasDirectivePayload)
        XCTAssertEqual(signal.scope.level, .global)
        XCTAssertTrue(signal.isEnabledByDefaultInV0)
    }

    func testExtendedScopesRemainEncodableButNotDefaultActive() throws {
        let signal = PreferenceSignal(
            signalId: "signal-style-001",
            turnId: "turn-assist-taskProgression-task-003-step-004",
            sessionId: "session-003",
            taskId: "task-003",
            stepId: "step-004",
            type: .style,
            evaluativeDecision: .fail,
            polarity: .discourage,
            scope: .windowPattern("Save Panel*", appBundleId: "com.apple.finder", appName: "Finder"),
            hint: "Keep review text concise inside save panels.",
            confidence: 0.79,
            evidenceIds: ["evidence-004"],
            proposedAction: "shorten_review_copy",
            promotionStatus: .candidate,
            timestamp: "2026-03-18T10:20:00Z"
        )

        let data = try JSONEncoder().encode(signal)
        let decoded = try JSONDecoder().decode(PreferenceSignal.self, from: data)

        XCTAssertEqual(decoded.scope.level, .windowPattern)
        XCTAssertEqual(decoded.scope.windowPattern, "Save Panel*")
        XCTAssertFalse(decoded.isEnabledByDefaultInV0)
        XCTAssertTrue(decoded.hasDirectivePayload)
    }
}
