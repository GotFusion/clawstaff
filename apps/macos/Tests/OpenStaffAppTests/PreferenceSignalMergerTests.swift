import XCTest
@testable import OpenStaffApp

final class PreferenceSignalMergerTests: XCTestCase {
    func testMergerCollapsesSameTurnScopeTypeAndPolarityIntoSingleSignal() {
        let first = makeSignal(
            signalId: "signal-001",
            confidence: 0.80,
            hint: "Prefer opening a new tab before a new window.",
            proposedAction: "prefer_new_tab",
            timestamp: "2026-03-19T09:00:00Z"
        )
        let second = makeSignal(
            signalId: "signal-002",
            confidence: 0.92,
            hint: "Prefer opening a new tab before a new window.",
            proposedAction: "prefer_new_tab",
            timestamp: "2026-03-19T09:05:00Z"
        )

        let result = PreferenceSignalMerger.merge([first, second])
        let entry = try! XCTUnwrap(result.entries.first)

        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(entry.sourceSignalIds, ["signal-001", "signal-002"])
        XCTAssertEqual(entry.sourceEvidenceIds, ["evidence-001", "evidence-002"])
        XCTAssertEqual(entry.signal.signalId, "signal-002")
        XCTAssertEqual(entry.signal.timestamp, "2026-03-19T09:05:00Z")
        XCTAssertEqual(entry.mergedConfidence, 0.86, accuracy: 0.0001)
        XCTAssertEqual(entry.conflictTags, [])
    }

    func testMergerMarksDirectiveConflictsAndOpposingPolarities() {
        let reinforce = makeSignal(
            signalId: "signal-reinforce-001",
            evaluativeDecision: .pass,
            polarity: .reinforce,
            hint: "Prefer Safari for this workflow.",
            proposedAction: "prefer_safari"
        )
        let discourage = makeSignal(
            signalId: "signal-discourage-001",
            evaluativeDecision: .fail,
            polarity: .discourage,
            hint: "Prefer Chrome for this workflow.",
            proposedAction: "prefer_chrome",
            promotionStatus: .confirmed,
            timestamp: "2026-03-19T09:10:00Z"
        )
        let conflictingDirective = makeSignal(
            signalId: "signal-discourage-002",
            evaluativeDecision: .fail,
            polarity: .discourage,
            hint: "Require teacher confirmation instead.",
            proposedAction: "require_teacher_confirmation",
            timestamp: "2026-03-19T09:11:00Z"
        )

        let result = PreferenceSignalMerger.merge([reinforce, discourage, conflictingDirective])

        XCTAssertEqual(result.entries.count, 2)
        let entriesByPolarity = Dictionary(uniqueKeysWithValues: result.entries.map { ($0.signal.polarity, $0) })
        let reinforceEntry = entriesByPolarity[.reinforce]
        let discourageEntry = entriesByPolarity[.discourage]

        XCTAssertTrue(reinforceEntry?.conflictTags.contains(.opposingPolarity) == true)
        XCTAssertTrue(discourageEntry?.conflictTags.contains(.opposingPolarity) == true)
        XCTAssertTrue(discourageEntry?.conflictTags.contains(.divergentHint) == true)
        XCTAssertTrue(discourageEntry?.conflictTags.contains(.divergentProposedAction) == true)
    }

    private func makeSignal(
        signalId: String,
        evaluativeDecision: PreferenceSignalEvaluativeDecision = .pass,
        polarity: PreferenceSignalPolarity = .reinforce,
        confidence: Double = 0.88,
        hint: String,
        proposedAction: String,
        promotionStatus: PreferenceSignalPromotionStatus = .candidate,
        timestamp: String = "2026-03-19T09:00:00Z"
    ) -> PreferenceSignal {
        PreferenceSignal(
            signalId: signalId,
            turnId: "turn-merged-001",
            traceId: "trace-merged-001",
            sessionId: "session-merged-001",
            taskId: "task-merged-001",
            stepId: "step-001",
            type: .procedure,
            evaluativeDecision: evaluativeDecision,
            polarity: polarity,
            scope: .taskFamily("browser.navigation"),
            hint: hint,
            confidence: confidence,
            evidenceIds: ["evidence-\(signalId.suffix(3))"],
            proposedAction: proposedAction,
            promotionStatus: promotionStatus,
            timestamp: timestamp
        )
    }
}
