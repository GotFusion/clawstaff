import Foundation
import XCTest
@testable import OpenStaffReplayVerifyCLI

final class SemanticActionExecutorTests: XCTestCase {
    func testDryRunClickResolvesRoleAndTitleWithoutCallingPerformer() {
        let snapshot = makeSnapshot(
            focusedElement: ReplayElementSnapshot(
                axPath: "AXWindow/AXButton[0]",
                role: "AXButton",
                title: "Open",
                identifier: "open-button",
                boundingRect: SemanticBoundingRect(x: 220, y: 140, width: 72, height: 28)
            ),
            visibleElements: [
                ReplayElementSnapshot(
                    axPath: "AXWindow/AXButton[0]",
                    role: "AXButton",
                    title: "Open",
                    identifier: "open-button",
                    boundingRect: SemanticBoundingRect(x: 220, y: 140, width: 72, height: 28)
                )
            ]
        )
        let performer = StubSemanticActionPerformer()
        let executor = SemanticActionExecutor(
            snapshotProvider: StaticReplayEnvironmentSnapshotProvider(snapshot: snapshot),
            resolver: SemanticTargetResolver(fingerprintCapture: StubFingerprintCapture(anchor: nil)),
            performer: performer,
            nowProvider: fixedNow
        )

        let report = executor.execute(action: makeClickAction(), dryRun: true)

        XCTAssertEqual(report.status, .succeeded)
        XCTAssertEqual(report.matchedLocatorType, "roleAndTitle")
        XCTAssertEqual(report.selectorHitPath, ["roleAndTitle"])
        XCTAssertTrue(performer.events.isEmpty)
    }

    func testDryRunBlocksCoordinateFallbackOnlyAction() {
        let performer = StubSemanticActionPerformer()
        let executor = SemanticActionExecutor(
            snapshotProvider: StaticReplayEnvironmentSnapshotProvider(snapshot: makeSnapshot()),
            resolver: SemanticTargetResolver(fingerprintCapture: StubFingerprintCapture(anchor: nil)),
            performer: performer,
            nowProvider: fixedNow
        )

        let report = executor.execute(
            action: SemanticActionStoreAction(
                actionId: "action-coordinate-001",
                sessionId: "session-001",
                taskId: "task-001",
                traceId: "trace-001",
                stepId: "step-001",
                actionType: "click",
                selector: [
                    "locatorType": "coordinateFallback",
                    "appBundleId": "com.test.app",
                    "windowTitlePattern": "^Main$",
                    "boundingRect": [
                        "x": 320.0,
                        "y": 240.0,
                        "width": 1.0,
                        "height": 1.0,
                        "coordinateSpace": "screen",
                    ],
                ],
                args: ["button": "left"],
                context: [:],
                preferredLocatorType: "coordinateFallback",
                manualReviewRequired: true,
                createdAt: "2026-03-27T13:10:00Z",
                updatedAt: "2026-03-27T13:10:00Z",
                targets: [],
                assertions: []
            ),
            dryRun: true
        )

        XCTAssertEqual(report.status, .blocked)
        XCTAssertEqual(report.errorCode, "SEM201-SEMANTIC-TARGET-REQUIRED")
        XCTAssertTrue(performer.events.isEmpty)
    }

    func testLiveShortcutDelegatesToPerformer() {
        let performer = StubSemanticActionPerformer()
        let executor = SemanticActionExecutor(
            snapshotProvider: StaticReplayEnvironmentSnapshotProvider(snapshot: makeSnapshot()),
            resolver: SemanticTargetResolver(fingerprintCapture: StubFingerprintCapture(anchor: nil)),
            performer: performer,
            nowProvider: fixedNow
        )

        let report = executor.execute(action: makeShortcutAction(), dryRun: false)

        XCTAssertEqual(report.status, .succeeded)
        XCTAssertEqual(performer.events, ["shortcut:command+k"])
    }

    func testDryRunDragProducesSourceAndTargetSelectorHitPath() {
        let snapshot = makeSnapshot(
            focusedElement: ReplayElementSnapshot(
                axPath: "AXWindow/AXList[0]/AXRow[1]",
                role: "AXRow",
                title: "Todo B",
                identifier: "todo-row-b",
                boundingRect: SemanticBoundingRect(x: 200, y: 180, width: 320, height: 28)
            ),
            visibleElements: [
                ReplayElementSnapshot(
                    axPath: "AXWindow/AXList[0]/AXRow[0]",
                    role: "AXRow",
                    title: "Todo A",
                    identifier: "todo-row-a",
                    boundingRect: SemanticBoundingRect(x: 200, y: 140, width: 320, height: 28)
                ),
                ReplayElementSnapshot(
                    axPath: "AXWindow/AXList[0]/AXRow[1]",
                    role: "AXRow",
                    title: "Todo B",
                    identifier: "todo-row-b",
                    boundingRect: SemanticBoundingRect(x: 200, y: 180, width: 320, height: 28)
                )
            ]
        )
        let performer = StubSemanticActionPerformer()
        let executor = SemanticActionExecutor(
            snapshotProvider: StaticReplayEnvironmentSnapshotProvider(snapshot: snapshot),
            resolver: SemanticTargetResolver(fingerprintCapture: StubFingerprintCapture(anchor: nil)),
            performer: performer,
            nowProvider: fixedNow
        )

        let report = executor.execute(action: makeDragAction(), dryRun: true)

        XCTAssertEqual(report.status, .succeeded)
        XCTAssertEqual(report.selectorHitPath, ["source:roleAndTitle", "target:roleAndTitle"])
        XCTAssertTrue(performer.events.isEmpty)
    }

    private func makeClickAction() -> SemanticActionStoreAction {
        SemanticActionStoreAction(
            actionId: "action-click-001",
            sessionId: "session-001",
            taskId: "task-001",
            traceId: "trace-001",
            stepId: "step-001",
            actionType: "click",
            selector: [
                "locatorType": "roleAndTitle",
                "appBundleId": "com.test.app",
                "windowTitlePattern": "^Main$",
                "elementRole": "AXButton",
                "elementTitle": "Open",
                "elementIdentifier": "open-button",
                "confidence": 0.92,
            ],
            args: ["button": "left"],
            context: [:],
            preferredLocatorType: "roleAndTitle",
            manualReviewRequired: false,
            createdAt: "2026-03-27T13:00:00Z",
            updatedAt: "2026-03-27T13:00:00Z",
            targets: [
                SemanticActionStoreTargetRecord(
                    targetId: "action-click-001:target:01",
                    targetRole: "primary",
                    ordinal: 1,
                    locatorType: "roleAndTitle",
                    selector: [
                        "locatorType": "roleAndTitle",
                        "appBundleId": "com.test.app",
                        "windowTitlePattern": "^Main$",
                        "elementRole": "AXButton",
                        "elementTitle": "Open",
                        "elementIdentifier": "open-button",
                        "confidence": 0.92,
                    ],
                    isPreferred: true
                )
            ],
            assertions: []
        )
    }

    private func makeShortcutAction() -> SemanticActionStoreAction {
        SemanticActionStoreAction(
            actionId: "action-shortcut-001",
            sessionId: "session-001",
            taskId: "task-001",
            traceId: "trace-001",
            stepId: "step-002",
            actionType: "shortcut",
            selector: [
                "selectorStrategy": "app_context",
                "appBundleId": "com.test.app",
            ],
            args: ["keys": ["command", "k"]],
            context: [:],
            preferredLocatorType: nil,
            manualReviewRequired: false,
            createdAt: "2026-03-27T13:01:00Z",
            updatedAt: "2026-03-27T13:01:00Z",
            targets: [],
            assertions: []
        )
    }

    private func makeDragAction() -> SemanticActionStoreAction {
        SemanticActionStoreAction(
            actionId: "action-drag-001",
            sessionId: "session-001",
            taskId: "task-001",
            traceId: "trace-001",
            stepId: "step-003",
            actionType: "drag",
            selector: [
                "locatorType": "roleAndTitle",
                "appBundleId": "com.test.app",
                "windowTitlePattern": "^Main$",
                "elementRole": "AXRow",
                "elementTitle": "Todo A",
                "elementIdentifier": "todo-row-a",
            ],
            args: [
                "intent": "list_reorder",
                "sourceSelector": [
                    "locatorType": "roleAndTitle",
                    "appBundleId": "com.test.app",
                    "windowTitlePattern": "^Main$",
                    "elementRole": "AXRow",
                    "elementTitle": "Todo A",
                    "elementIdentifier": "todo-row-a",
                ],
                "targetSelector": [
                    "locatorType": "roleAndTitle",
                    "appBundleId": "com.test.app",
                    "windowTitlePattern": "^Main$",
                    "elementRole": "AXRow",
                    "elementTitle": "Todo B",
                    "elementIdentifier": "todo-row-b",
                ],
            ],
            context: [:],
            preferredLocatorType: "roleAndTitle",
            manualReviewRequired: true,
            createdAt: "2026-03-27T13:02:00Z",
            updatedAt: "2026-03-27T13:02:00Z",
            targets: [
                SemanticActionStoreTargetRecord(
                    targetId: "action-drag-001:target:source:01",
                    targetRole: "source",
                    ordinal: 1,
                    locatorType: "roleAndTitle",
                    selector: [
                        "locatorType": "roleAndTitle",
                        "appBundleId": "com.test.app",
                        "windowTitlePattern": "^Main$",
                        "elementRole": "AXRow",
                        "elementTitle": "Todo A",
                        "elementIdentifier": "todo-row-a",
                    ],
                    isPreferred: true
                ),
                SemanticActionStoreTargetRecord(
                    targetId: "action-drag-001:target:target:01",
                    targetRole: "target",
                    ordinal: 2,
                    locatorType: "roleAndTitle",
                    selector: [
                        "locatorType": "roleAndTitle",
                        "appBundleId": "com.test.app",
                        "windowTitlePattern": "^Main$",
                        "elementRole": "AXRow",
                        "elementTitle": "Todo B",
                        "elementIdentifier": "todo-row-b",
                    ],
                    isPreferred: true
                ),
            ],
            assertions: []
        )
    }

    private func makeSnapshot(
        focusedElement: ReplayElementSnapshot? = nil,
        visibleElements: [ReplayElementSnapshot] = []
    ) -> ReplayEnvironmentSnapshot {
        ReplayEnvironmentSnapshot(
            capturedAt: "2026-03-27T13:05:00Z",
            appName: "TestApp",
            appBundleId: "com.test.app",
            windowTitle: "Main",
            windowId: "1",
            windowSignature: WindowSignature(
                signature: "window-signature-001",
                normalizedTitle: "main",
                role: "AXWindow",
                subrole: "AXStandardWindow",
                sizeBucket: "12x8"
            ),
            focusedElement: focusedElement,
            visibleElements: visibleElements
        )
    }

    private func fixedNow() -> Date {
        Date(timeIntervalSince1970: 1_743_082_200)
    }
}

private struct StubFingerprintCapture: SemanticScreenFingerprintCapturing {
    let anchor: SemanticImageAnchor?

    func capture(rect: SemanticBoundingRect) -> SemanticImageAnchor? {
        anchor
    }
}

private final class StubSemanticActionPerformer: SemanticActionPerforming {
    var events: [String] = []

    func activateApp(bundleId: String) -> Bool {
        events.append("activate:\(bundleId)")
        return true
    }

    func focusWindow(appBundleId: String, windowTitlePattern: String?, windowSignature: String?) -> SemanticActionPerformOutcome {
        events.append("focus:\(appBundleId)")
        return SemanticActionPerformOutcome(status: .succeeded, message: "focused", errorCode: nil)
    }

    func pressElement(_ snapshot: ReplayElementSnapshot, appBundleId: String) -> SemanticActionPerformOutcome {
        let label = snapshot.identifier ?? snapshot.title ?? "unknown"
        events.append("press:\(label)")
        return SemanticActionPerformOutcome(status: .succeeded, message: "pressed", errorCode: nil)
    }

    func setText(_ snapshot: ReplayElementSnapshot, text: String, appBundleId: String) -> SemanticActionPerformOutcome {
        events.append("type:\(text)")
        return SemanticActionPerformOutcome(status: .succeeded, message: "typed", errorCode: nil)
    }

    func sendShortcut(keys: [String], appBundleId: String?) -> SemanticActionPerformOutcome {
        let joinedKeys = keys.joined(separator: "+")
        events.append("shortcut:\(joinedKeys)")
        return SemanticActionPerformOutcome(status: .succeeded, message: "shortcut", errorCode: nil)
    }

    func moveWindow(source: ReplayElementSnapshot, target: ReplayElementSnapshot, appBundleId: String) -> SemanticActionPerformOutcome {
        let sourceLabel = source.identifier ?? "source"
        let targetLabel = target.identifier ?? "target"
        events.append("drag:\(sourceLabel)->\(targetLabel)")
        return SemanticActionPerformOutcome(status: .succeeded, message: "dragged", errorCode: nil)
    }
}
