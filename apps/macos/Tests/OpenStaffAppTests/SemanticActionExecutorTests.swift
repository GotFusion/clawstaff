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

    func testContextGuardBlocksWrongFrontmostAppBeforeResolution() {
        let performer = StubSemanticActionPerformer()
        let executor = SemanticActionExecutor(
            snapshotProvider: StaticReplayEnvironmentSnapshotProvider(
                snapshot: makeSnapshot(appName: "OtherApp", appBundleId: "com.other.app")
            ),
            resolver: SemanticTargetResolver(fingerprintCapture: StubFingerprintCapture(anchor: nil)),
            performer: performer,
            nowProvider: fixedNow
        )

        let report = executor.execute(action: makeClickAction(), dryRun: true)

        XCTAssertEqual(report.status, SemanticActionExecutionStatus.blocked)
        XCTAssertEqual(report.errorCode, "SEM202-CONTEXT-MISMATCH")
        XCTAssertEqual(report.contextGuard?.status, SemanticActionContextGuardStatus.blocked)
        XCTAssertEqual(report.contextGuard?.mismatches.first?.dimension, "requiredFrontmostApp")
        XCTAssertEqual(report.contextGuard?.actual.appBundleId, "com.other.app")
        XCTAssertTrue(performer.events.isEmpty)
    }

    func testContextGuardBlocksWindowMismatchForFocusWindowUsingFromWindowTitle() {
        let performer = StubSemanticActionPerformer()
        let executor = SemanticActionExecutor(
            snapshotProvider: StaticReplayEnvironmentSnapshotProvider(snapshot: makeSnapshot(windowTitle: "Dashboard")),
            resolver: SemanticTargetResolver(fingerprintCapture: StubFingerprintCapture(anchor: nil)),
            performer: performer,
            nowProvider: fixedNow
        )

        let report = executor.execute(
            action: SemanticActionStoreAction(
                actionId: "action-focus-001",
                sessionId: "session-001",
                taskId: "task-001",
                traceId: "trace-001",
                stepId: "step-focus-001",
                actionType: "focus_window",
                selector: [
                    "selectorStrategy": "window_context",
                    "appBundleId": "com.test.app",
                    "windowTitlePattern": "^Search Results$",
                ],
                args: [
                    "fromWindowTitle": "Inbox",
                    "toWindowTitle": "Search Results",
                ],
                context: [:],
                preferredLocatorType: nil,
                manualReviewRequired: false,
                createdAt: "2026-03-27T13:03:00Z",
                updatedAt: "2026-03-27T13:03:00Z",
                targets: [],
                assertions: []
            ),
            dryRun: true
        )

        XCTAssertEqual(report.status, SemanticActionExecutionStatus.blocked)
        XCTAssertEqual(report.errorCode, "SEM202-CONTEXT-MISMATCH")
        XCTAssertEqual(report.contextGuard?.mismatches.first?.dimension, "windowTitlePattern")
        XCTAssertEqual(report.contextGuard?.actual.windowTitle, "Dashboard")
        XCTAssertTrue(performer.events.isEmpty)
    }

    func testContextGuardBlocksURLHostMismatchForBrowserAction() {
        let performer = StubSemanticActionPerformer()
        let executor = SemanticActionExecutor(
            snapshotProvider: StaticReplayEnvironmentSnapshotProvider(
                snapshot: makeSnapshot(
                    url: "https://docs.github.com/en",
                    urlHost: "docs.github.com"
                )
            ),
            resolver: SemanticTargetResolver(fingerprintCapture: StubFingerprintCapture(anchor: nil)),
            performer: performer,
            nowProvider: fixedNow
        )

        let action = SemanticActionStoreAction(
            actionId: "action-browser-click-001",
            sessionId: "session-001",
            taskId: "task-001",
            traceId: "trace-001",
            stepId: "step-004",
            actionType: "click",
            selector: [
                "locatorType": "roleAndTitle",
                "appBundleId": "com.test.app",
                "windowTitlePattern": "^Main$",
                "elementRole": "AXButton",
                "elementTitle": "Open",
                "elementIdentifier": "open-button",
                "urlHost": "github.com",
            ],
            args: ["button": "left"],
            context: [
                "appContext": [
                    "appBundleId": "com.test.app",
                    "windowTitle": "Main",
                    "url": "https://github.com/openstaff",
                    "urlHost": "github.com",
                ]
            ],
            preferredLocatorType: "roleAndTitle",
            manualReviewRequired: false,
            createdAt: "2026-03-27T13:04:00Z",
            updatedAt: "2026-03-27T13:04:00Z",
            targets: [
                SemanticActionStoreTargetRecord(
                    targetId: "action-browser-click-001:target:01",
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
                        "urlHost": "github.com",
                    ],
                    isPreferred: true
                )
            ],
            assertions: []
        )

        let report = executor.execute(action: action, dryRun: true)

        XCTAssertEqual(report.status, SemanticActionExecutionStatus.blocked)
        XCTAssertEqual(report.errorCode, "SEM202-CONTEXT-MISMATCH")
        XCTAssertEqual(report.contextGuard?.mismatches.first?.dimension, "urlHost")
        XCTAssertEqual(report.contextGuard?.actual.urlHost, "docs.github.com")
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
        XCTAssertEqual(report.postAssertions?.status, .passed)
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

        XCTAssertEqual(report.status, .blocked)
        XCTAssertEqual(report.errorCode, "SEM302-TEACHER-CONFIRMATION-REQUIRED")
        XCTAssertEqual(report.teacherConfirmation?.status, .required)
        XCTAssertEqual(report.teacherConfirmation?.reasons.first?.code, "SEM302-MANUAL-REVIEW-REQUIRED")
        XCTAssertTrue(performer.events.isEmpty)
    }

    func testDryRunDragSucceedsAfterTeacherConfirmationAndKeepsReviewPayload() {
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

        let report = executor.execute(
            action: makeDragAction(),
            dryRun: true,
            teacherConfirmed: true
        )

        XCTAssertEqual(report.status, .succeeded)
        XCTAssertEqual(report.selectorHitPath, ["source:roleAndTitle", "target:roleAndTitle"])
        XCTAssertEqual(report.teacherConfirmation?.status, .approved)
        XCTAssertEqual(report.teacherConfirmation?.selectorCandidates.count, 2)
        XCTAssertTrue(performer.events.isEmpty)
    }

    func testDryRunLowConfidenceClickRequiresTeacherConfirmation() {
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

        let report = executor.execute(
            action: makeClickAction(confidence: 0.42),
            dryRun: true
        )

        XCTAssertEqual(report.status, .blocked)
        XCTAssertEqual(report.errorCode, "SEM302-TEACHER-CONFIRMATION-REQUIRED")
        XCTAssertEqual(report.teacherConfirmation?.status, .required)
        XCTAssertEqual(report.teacherConfirmation?.reasons.last?.code, "SEM302-LOW-SELECTOR-CONFIDENCE")
        XCTAssertTrue(performer.events.isEmpty)
    }

    func testCustomTeacherConfirmationPolicyCanLowerConfidenceThreshold() {
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

        let report = executor.execute(
            action: makeClickAction(confidence: 0.42),
            dryRun: true,
            confirmationPolicy: SemanticActionTeacherConfirmationPolicy(
                minimumConfidence: 0.30,
                requireManualReviewActions: true,
                requireForSwitchApp: true,
                requireForDrag: true,
                requireForBulkType: true,
                bulkTypeMinimumLength: 20
            )
        )

        XCTAssertEqual(report.status, .succeeded)
        XCTAssertNil(report.teacherConfirmation)
        XCTAssertEqual(report.matchedLocatorType, "roleAndTitle")
        XCTAssertTrue(performer.events.isEmpty)
    }

    func testLiveSwitchAppFailsWhenPostAssertionDoesNotObserveTargetApp() {
        let performer = StubSemanticActionPerformer()
        let provider = SequenceReplayEnvironmentSnapshotProvider(
            snapshots: [
                makeSnapshot(appName: "SourceApp", appBundleId: "com.source.app"),
                makeSnapshot(appName: "OtherApp", appBundleId: "com.other.app"),
            ]
        )
        let executor = SemanticActionExecutor(
            snapshotProvider: provider,
            resolver: SemanticTargetResolver(fingerprintCapture: StubFingerprintCapture(anchor: nil)),
            performer: performer,
            nowProvider: fixedNow
        )

        let action = SemanticActionStoreAction(
            actionId: "action-switch-app-001",
            sessionId: "session-001",
            taskId: "task-001",
            traceId: "trace-switch-001",
            stepId: "step-switch-001",
            actionType: "switch_app",
            selector: [
                "selectorStrategy": "app_context",
                "appBundleId": "com.target.app",
            ],
            args: [
                "fromAppBundleId": "com.source.app",
                "fromAppName": "SourceApp",
                "toAppBundleId": "com.target.app",
                "toAppName": "TargetApp",
            ],
            context: [:],
            preferredLocatorType: nil,
            manualReviewRequired: false,
            createdAt: "2026-03-28T08:00:00Z",
            updatedAt: "2026-03-28T08:00:00Z",
            targets: [],
            assertions: []
        )

        let report = executor.execute(
            action: action,
            dryRun: false,
            teacherConfirmed: true
        )

        XCTAssertEqual(report.status, .failed)
        XCTAssertEqual(report.errorCode, "SEM203-ASSERTION-FAILED")
        XCTAssertEqual(report.postAssertions?.status, .failed)
        XCTAssertEqual(
            report.postAssertions?.assertions.first(where: { $0.status == .failed })?.assertionType,
            "requiredFrontmostApp"
        )
        XCTAssertEqual(performer.events, ["activate:com.target.app"])
    }

    func testLiveTypePassesTextValuePostAssertion() {
        let preResolutionSnapshot = makeSnapshot(
            focusedElement: ReplayElementSnapshot(
                axPath: "AXWindow/AXTextField[0]",
                role: "AXTextField",
                title: "Search",
                identifier: "search-field",
                boundingRect: SemanticBoundingRect(x: 220, y: 140, width: 240, height: 32)
            ),
            visibleElements: [
                ReplayElementSnapshot(
                    axPath: "AXWindow/AXTextField[0]",
                    role: "AXTextField",
                    title: "Search",
                    identifier: "search-field",
                    boundingRect: SemanticBoundingRect(x: 220, y: 140, width: 240, height: 32)
                )
            ]
        )
        let postSnapshot = makeSnapshot(
            focusedElement: ReplayElementSnapshot(
                axPath: "AXWindow/AXTextField[0]",
                role: "AXTextField",
                title: "Search",
                identifier: "search-field",
                valueText: "hello world",
                boundingRect: SemanticBoundingRect(x: 220, y: 140, width: 240, height: 32)
            ),
            visibleElements: [
                ReplayElementSnapshot(
                    axPath: "AXWindow/AXTextField[0]",
                    role: "AXTextField",
                    title: "Search",
                    identifier: "search-field",
                    valueText: "hello world",
                    boundingRect: SemanticBoundingRect(x: 220, y: 140, width: 240, height: 32)
                )
            ]
        )
        let performer = StubSemanticActionPerformer()
        let provider = SequenceReplayEnvironmentSnapshotProvider(
            snapshots: [preResolutionSnapshot, preResolutionSnapshot, postSnapshot]
        )
        let executor = SemanticActionExecutor(
            snapshotProvider: provider,
            resolver: SemanticTargetResolver(fingerprintCapture: StubFingerprintCapture(anchor: nil)),
            performer: performer,
            nowProvider: fixedNow
        )

        let action = SemanticActionStoreAction(
            actionId: "action-type-001",
            sessionId: "session-001",
            taskId: "task-001",
            traceId: "trace-type-001",
            stepId: "step-type-001",
            actionType: "type",
            selector: [
                "locatorType": "roleAndTitle",
                "appBundleId": "com.test.app",
                "windowTitlePattern": "^Main$",
                "elementRole": "AXTextField",
                "elementTitle": "Search",
                "elementIdentifier": "search-field",
            ],
            args: ["text": "hello"],
            context: [:],
            preferredLocatorType: "roleAndTitle",
            manualReviewRequired: false,
            createdAt: "2026-03-28T08:01:00Z",
            updatedAt: "2026-03-28T08:01:00Z",
            targets: [
                SemanticActionStoreTargetRecord(
                    targetId: "action-type-001:target:01",
                    targetRole: "primary",
                    ordinal: 1,
                    locatorType: "roleAndTitle",
                    selector: [
                        "locatorType": "roleAndTitle",
                        "appBundleId": "com.test.app",
                        "windowTitlePattern": "^Main$",
                        "elementRole": "AXTextField",
                        "elementTitle": "Search",
                        "elementIdentifier": "search-field",
                    ],
                    isPreferred: true
                )
            ],
            assertions: []
        )

        let report = executor.execute(action: action, dryRun: false)

        XCTAssertEqual(report.status, .succeeded)
        XCTAssertEqual(report.postAssertions?.status, .passed)
        XCTAssertEqual(
            report.postAssertions?.assertions.first(where: { $0.assertionType == "textValueContains" })?.status,
            .passed
        )
        XCTAssertEqual(performer.events, ["activate:com.test.app", "type:hello"])
    }

    private func makeClickAction(confidence: Double = 0.92) -> SemanticActionStoreAction {
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
                "confidence": confidence,
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
                        "confidence": confidence,
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
        appName: String = "TestApp",
        appBundleId: String = "com.test.app",
        windowTitle: String = "Main",
        url: String? = nil,
        urlHost: String? = nil,
        focusedElement: ReplayElementSnapshot? = nil,
        visibleElements: [ReplayElementSnapshot] = []
    ) -> ReplayEnvironmentSnapshot {
        ReplayEnvironmentSnapshot(
            capturedAt: "2026-03-27T13:05:00Z",
            appName: appName,
            appBundleId: appBundleId,
            windowTitle: windowTitle,
            windowId: "1",
            windowSignature: WindowSignature(
                signature: "window-signature-001",
                normalizedTitle: windowTitle.lowercased(),
                role: "AXWindow",
                subrole: "AXStandardWindow",
                sizeBucket: "12x8"
            ),
            url: url,
            urlHost: urlHost,
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

private final class SequenceReplayEnvironmentSnapshotProvider: ReplayEnvironmentSnapshotProviding {
    private var snapshots: [ReplayEnvironmentSnapshot]
    private var index: Int = 0

    init(snapshots: [ReplayEnvironmentSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot() -> ReplayEnvironmentSnapshot {
        guard !snapshots.isEmpty else {
            fatalError("SequenceReplayEnvironmentSnapshotProvider requires at least one snapshot.")
        }
        let value = snapshots[min(index, snapshots.count - 1)]
        index += 1
        return value
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
