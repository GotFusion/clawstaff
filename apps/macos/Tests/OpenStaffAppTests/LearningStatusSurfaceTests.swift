import Foundation
import XCTest
@testable import OpenStaffApp

@MainActor
final class LearningStatusSurfaceTests: XCTestCase {
    func testManualPauseAndResumePreservesSessionAndAccumulatesEvents() {
        let capture = FakeModeObservationCaptureService()
        let contextProvider = FakeLearningContextSnapshotProvider(
            snapshot: ContextSnapshot(
                appName: "Finder",
                appBundleId: "com.apple.finder",
                windowTitle: "Documents",
                windowId: "1"
            )
        )
        let viewModel = OpenStaffDashboardViewModel(
            modeObservationCapture: capture,
            permissionSnapshotProvider: { _ in
                PermissionSnapshot(accessibilityTrusted: true, dataDirectoryWritable: true)
            },
            learningContextSnapshotProvider: contextProvider,
            learningLastSuccessfulWriteProvider: FakeLearningLastSuccessfulWriteProvider()
        )

        viewModel.startMode(.teaching)
        XCTAssertEqual(viewModel.learningSessionState.status, .on)

        capture.emitCapturedCount(4)
        waitForMainQueue()

        let sessionId = viewModel.activeObservationSessionId
        XCTAssertEqual(viewModel.capturedEventCount, 4)

        viewModel.pauseLearningCapture()

        XCTAssertEqual(viewModel.learningSessionState.status, .paused)
        XCTAssertTrue(viewModel.learningSessionState.teacherPaused)
        XCTAssertFalse(capture.isRunning)
        XCTAssertEqual(viewModel.activeObservationSessionId, sessionId)
        XCTAssertEqual(viewModel.capturedEventCount, 4)

        viewModel.resumeLearningCapture()

        XCTAssertEqual(viewModel.learningSessionState.status, .on)
        XCTAssertFalse(viewModel.learningSessionState.teacherPaused)
        XCTAssertTrue(capture.isRunning)
        XCTAssertEqual(viewModel.activeObservationSessionId, sessionId)

        capture.emitCapturedCount(2)
        waitForMainQueue()

        XCTAssertEqual(viewModel.capturedEventCount, 6)
    }

    func testExcludedStatusWhenFrontmostAppIsOpenStaff() {
        let capture = FakeModeObservationCaptureService()
        let contextProvider = FakeLearningContextSnapshotProvider(
            snapshot: ContextSnapshot(
                appName: "OpenStaff",
                appBundleId: "dev.openstaff.app",
                windowTitle: "OpenStaff Console",
                windowId: "2"
            )
        )
        let viewModel = OpenStaffDashboardViewModel(
            modeObservationCapture: capture,
            permissionSnapshotProvider: { _ in
                PermissionSnapshot(accessibilityTrusted: true, dataDirectoryWritable: true)
            },
            learningContextSnapshotProvider: contextProvider,
            learningLastSuccessfulWriteProvider: FakeLearningLastSuccessfulWriteProvider()
        )

        viewModel.startMode(.teaching)

        XCTAssertEqual(viewModel.learningSessionState.status, .excluded)
        XCTAssertFalse(capture.isRunning)
        XCTAssertNotNil(viewModel.activeObservationSessionId)
    }

    func testSensitiveMutedStatusWhenWindowMatchesSensitivePolicy() {
        let capture = FakeModeObservationCaptureService()
        let contextProvider = FakeLearningContextSnapshotProvider(
            snapshot: ContextSnapshot(
                appName: "Safari",
                appBundleId: "com.apple.Safari",
                windowTitle: "Checkout Payment",
                windowId: "3"
            )
        )
        let viewModel = OpenStaffDashboardViewModel(
            modeObservationCapture: capture,
            permissionSnapshotProvider: { _ in
                PermissionSnapshot(accessibilityTrusted: true, dataDirectoryWritable: true)
            },
            learningContextSnapshotProvider: contextProvider,
            learningLastSuccessfulWriteProvider: FakeLearningLastSuccessfulWriteProvider()
        )

        viewModel.startMode(.teaching)

        XCTAssertEqual(viewModel.learningSessionState.status, .sensitiveMuted)
        XCTAssertFalse(capture.isRunning)
        XCTAssertTrue(viewModel.learningSessionState.statusReason.contains("敏感"))
    }

    func testRawEventLastSuccessfulWriteProviderReturnsLatestModificationDate() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("openstaff-learning-status-\(UUID().uuidString)", isDirectory: true)
        let dayOne = root.appendingPathComponent("2026-03-17", isDirectory: true)
        let dayTwo = root.appendingPathComponent("2026-03-18", isDirectory: true)
        try fileManager.createDirectory(at: dayOne, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: dayTwo, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: root)
        }

        let oldFile = dayOne.appendingPathComponent("session-old.jsonl", isDirectory: false)
        let newFile = dayTwo.appendingPathComponent("session-new.jsonl", isDirectory: false)
        try "{}\n".write(to: oldFile, atomically: true, encoding: .utf8)
        try "{}\n".write(to: newFile, atomically: true, encoding: .utf8)

        let oldDate = Date(timeIntervalSince1970: 1_763_000_000)
        let newDate = Date(timeIntervalSince1970: 1_764_000_000)
        try fileManager.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldFile.path)
        try fileManager.setAttributes([.modificationDate: newDate], ofItemAtPath: newFile.path)

        let provider = RawEventLastSuccessfulWriteProvider()
        XCTAssertEqual(provider.latestSuccessfulWriteAt(rawEventsRootDirectory: root), newDate)
    }

    private func waitForMainQueue() {
        let expectation = expectation(description: "main queue drain")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
}

private final class FakeLearningContextSnapshotProvider: LearningContextSnapshotProviding {
    var snapshotValue: ContextSnapshot

    init(snapshot: ContextSnapshot) {
        self.snapshotValue = snapshot
    }

    func snapshot(includeWindowContext: Bool) -> ContextSnapshot {
        snapshotValue
    }
}

private struct FakeLearningLastSuccessfulWriteProvider: LearningLastSuccessfulWriteProviding {
    var lastWrite: Date? = nil

    func latestSuccessfulWriteAt(rawEventsRootDirectory: URL) -> Date? {
        lastWrite
    }
}

private final class FakeModeObservationCaptureService: ModeObservationCaptureControlling {
    var onFatalError: ((Error) -> Void)?
    var onEventCaptured: ((Int) -> Void)?

    private(set) var isRunning = false
    private(set) var capturedEventCount = 0
    private(set) var lastSessionId: String?
    private(set) var lastIncludeWindowContext: Bool?

    func start(sessionId: String, includeWindowContext: Bool) throws {
        isRunning = true
        capturedEventCount = 0
        lastSessionId = sessionId
        lastIncludeWindowContext = includeWindowContext
        onEventCaptured?(0)
    }

    func stop() {
        isRunning = false
        capturedEventCount = 0
        onEventCaptured?(0)
    }

    func emitCapturedCount(_ count: Int) {
        capturedEventCount = count
        onEventCaptured?(count)
    }
}
