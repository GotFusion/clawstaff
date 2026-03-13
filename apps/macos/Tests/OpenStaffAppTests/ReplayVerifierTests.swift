import Foundation
import XCTest
@testable import OpenStaffApp

final class ReplayVerifierTests: XCTestCase {
    func testSemanticTargetResolverPrefersAXPathOverRoleAndTitle() {
        let snapshot = makeSnapshot(
            visibleElements: [
                ReplayElementSnapshot(
                    axPath: "AXWindow/AXGroup[0]/AXButton[1]",
                    role: "AXButton",
                    title: "Open",
                    identifier: "finder.open-button",
                    boundingRect: SemanticBoundingRect(x: 220, y: 140, width: 72, height: 28)
                )
            ]
        )
        let resolver = SemanticTargetResolver(
            fingerprintCapture: StubFingerprintCapture(anchor: nil)
        )
        let targets = [
            SemanticTarget(
                locatorType: .roleAndTitle,
                appBundleId: "com.test.app",
                windowTitlePattern: "^Main$",
                elementRole: "AXButton",
                elementTitle: "Open",
                elementIdentifier: "finder.open-button",
                confidence: 0.68,
                source: .capture
            ),
            SemanticTarget(
                locatorType: .axPath,
                appBundleId: "com.test.app",
                windowTitlePattern: "^Main$",
                axPath: "AXWindow/AXGroup[0]/AXButton[1]",
                confidence: 0.84,
                source: .capture
            )
        ]

        let resolution = resolver.resolve(targets: targets, in: snapshot)

        XCTAssertEqual(resolution.status, .resolved)
        XCTAssertEqual(resolution.matchedLocatorType, .axPath)
    }

    func testReplayVerifierResolvesRoleAndTitleFromVisibleElements() {
        let snapshot = makeSnapshot(
            visibleElements: [
                ReplayElementSnapshot(
                    axPath: "AXWindow/AXLink[0]",
                    role: "AXLink",
                    title: "Issues",
                    identifier: "repo-nav.issues",
                    boundingRect: SemanticBoundingRect(x: 888, y: 582, width: 74, height: 30)
                )
            ]
        )
        let verifier = ReplayVerifier(
            snapshotProvider: StaticReplayEnvironmentSnapshotProvider(snapshot: snapshot),
            resolver: SemanticTargetResolver(fingerprintCapture: StubFingerprintCapture(anchor: nil)),
            nowProvider: fixedNow
        )

        let report = verifier.verify(item: makeKnowledgeItem(stepTarget: KnowledgeStepTarget(
            coordinate: PointerLocation(x: 911, y: 601),
            semanticTargets: [
                SemanticTarget(
                    locatorType: .roleAndTitle,
                    appBundleId: "com.test.app",
                    windowTitlePattern: "^Main$",
                    elementRole: "AXLink",
                    elementTitle: "Issues",
                    elementIdentifier: "repo-nav.issues",
                    confidence: 0.68,
                    source: .capture
                )
            ],
            preferredLocatorType: .roleAndTitle
        )))

        XCTAssertEqual(report.summary.resolvedSteps, 1)
        XCTAssertEqual(report.steps[0].status, .resolved)
        XCTAssertEqual(report.steps[0].matchedLocatorType, .roleAndTitle)
    }

    func testReplayVerifierReportsWindowMismatch() {
        let snapshot = makeSnapshot(windowTitle: "Other")
        let verifier = ReplayVerifier(
            snapshotProvider: StaticReplayEnvironmentSnapshotProvider(snapshot: snapshot),
            resolver: SemanticTargetResolver(fingerprintCapture: StubFingerprintCapture(anchor: nil)),
            nowProvider: fixedNow
        )
        let report = verifier.verify(item: makeKnowledgeItem(stepTarget: KnowledgeStepTarget(
            coordinate: PointerLocation(x: 320, y: 240),
            semanticTargets: [
                SemanticTarget(
                    locatorType: .roleAndTitle,
                    appBundleId: "com.test.app",
                    windowTitlePattern: "^Main$",
                    elementRole: "AXButton",
                    elementTitle: "Open",
                    confidence: 0.68,
                    source: .capture
                )
            ],
            preferredLocatorType: .roleAndTitle
        )))

        XCTAssertEqual(report.steps[0].status, .failed)
        XCTAssertEqual(report.steps[0].failureReason, .windowMismatch)
    }

    func testReplayVerifierReportsTextAnchorChanged() {
        let snapshot = makeSnapshot(
            visibleElements: [
                ReplayElementSnapshot(
                    axPath: "AXWindow/AXGroup[0]/AXButton[0]",
                    role: "AXButton",
                    title: "Open Workspace",
                    identifier: "finder.open-button",
                    boundingRect: SemanticBoundingRect(x: 220, y: 140, width: 72, height: 28)
                )
            ]
        )
        let verifier = ReplayVerifier(
            snapshotProvider: StaticReplayEnvironmentSnapshotProvider(snapshot: snapshot),
            resolver: SemanticTargetResolver(fingerprintCapture: StubFingerprintCapture(anchor: nil)),
            nowProvider: fixedNow
        )
        let report = verifier.verify(item: makeKnowledgeItem(stepTarget: KnowledgeStepTarget(
            coordinate: PointerLocation(x: 320, y: 240),
            semanticTargets: [
                SemanticTarget(
                    locatorType: .textAnchor,
                    appBundleId: "com.test.app",
                    windowTitlePattern: "^Main$",
                    elementRole: "AXButton",
                    elementIdentifier: "finder.open-button",
                    textAnchor: "Open Project",
                    confidence: 0.56,
                    source: .capture
                )
            ],
            preferredLocatorType: .textAnchor
        )))

        XCTAssertEqual(report.steps[0].status, .failed)
        XCTAssertEqual(report.steps[0].failureReason, .textAnchorChanged)
    }

    func testReplayVerifierDegradesLegacyCoordinateOnlyTarget() {
        let snapshot = makeSnapshot()
        let verifier = ReplayVerifier(
            snapshotProvider: StaticReplayEnvironmentSnapshotProvider(snapshot: snapshot),
            resolver: SemanticTargetResolver(fingerprintCapture: StubFingerprintCapture(anchor: nil)),
            nowProvider: fixedNow
        )
        let report = verifier.verify(item: makeKnowledgeItem(stepTarget: KnowledgeStepTarget(
            coordinate: PointerLocation(x: 320, y: 240),
            semanticTargets: [],
            preferredLocatorType: nil
        )))

        XCTAssertEqual(report.steps[0].status, .degraded)
        XCTAssertEqual(report.steps[0].failureReason, .coordinateFallbackOnly)
        XCTAssertEqual(report.summary.degradedSteps, 1)
    }

    private func makeKnowledgeItem(stepTarget: KnowledgeStepTarget?) -> KnowledgeItem {
        KnowledgeItem(
            knowledgeItemId: "ki-task-session-test-001",
            taskId: "task-session-test-001",
            sessionId: "session-test",
            goal: "goal",
            summary: "summary",
            steps: [
                KnowledgeStep(
                    stepId: "step-001",
                    instruction: "点击 Open",
                    sourceEventIds: ["evt-1"],
                    target: stepTarget
                )
            ],
            context: KnowledgeContext(
                appName: "TestApp",
                appBundleId: "com.test.app",
                windowTitle: "Main",
                windowId: "1"
            ),
            constraints: [],
            source: KnowledgeSource(
                taskChunkSchemaVersion: "knowledge.task-chunk.v0",
                startTimestamp: "2026-03-13T10:00:00Z",
                endTimestamp: "2026-03-13T10:00:10Z",
                eventCount: 1,
                boundaryReason: .sessionEnd
            ),
            createdAt: "2026-03-13T10:01:00Z"
        )
    }

    private func makeSnapshot(
        windowTitle: String = "Main",
        visibleElements: [ReplayElementSnapshot] = []
    ) -> ReplayEnvironmentSnapshot {
        ReplayEnvironmentSnapshot(
            capturedAt: "2026-03-13T10:05:00Z",
            appName: "TestApp",
            appBundleId: "com.test.app",
            windowTitle: windowTitle,
            windowId: "1",
            windowSignature: WindowSignature(
                signature: "window-signature-001",
                normalizedTitle: windowTitle.lowercased(),
                role: "AXWindow",
                subrole: "AXStandardWindow",
                sizeBucket: "12x8"
            ),
            focusedElement: visibleElements.first,
            visibleElements: visibleElements
        )
    }

    private func fixedNow() -> Date {
        Date(timeIntervalSince1970: 1_741_862_400)
    }
}

private struct StubFingerprintCapture: SemanticScreenFingerprintCapturing {
    let anchor: SemanticImageAnchor?

    func capture(rect: SemanticBoundingRect) -> SemanticImageAnchor? {
        anchor
    }
}
