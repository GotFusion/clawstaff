import Foundation
import XCTest
@testable import OpenStaffApp

@MainActor
final class TeachingModeCaptureTests: XCTestCase {
    func testTeachingModeStartTriggersObservationCaptureAndUpdatesEventCount() {
        let capture = FakeModeObservationCaptureService()
        let viewModel = OpenStaffDashboardViewModel(
            modeObservationCapture: capture,
            permissionSnapshotProvider: { _ in
                PermissionSnapshot(accessibilityTrusted: false, dataDirectoryWritable: true)
            }
        )

        viewModel.startMode(.teaching)

        XCTAssertEqual(capture.startCallCount, 1)
        XCTAssertEqual(capture.lastIncludeWindowContext, false)
        XCTAssertEqual(viewModel.runningMode, .teaching)
        XCTAssertNotNil(viewModel.activeObservationSessionId)
        XCTAssertTrue(viewModel.transitionMessage?.contains("降级采集") == true)
        XCTAssertTrue(viewModel.captureStatusText?.contains("点击事件：0") == true)

        capture.emitCapturedCount(3)
        waitForMainQueue()

        XCTAssertEqual(viewModel.capturedEventCount, 3)
    }

    func testEmergencyStopStopsObservationCapture() {
        let capture = FakeModeObservationCaptureService()
        let viewModel = OpenStaffDashboardViewModel(
            modeObservationCapture: capture,
            permissionSnapshotProvider: { _ in
                PermissionSnapshot(accessibilityTrusted: true, dataDirectoryWritable: true)
            }
        )

        viewModel.startMode(.teaching)
        capture.emitCapturedCount(2)
        waitForMainQueue()
        XCTAssertEqual(viewModel.capturedEventCount, 2)

        viewModel.activateEmergencyStop(source: .uiButton)

        XCTAssertEqual(capture.stopCallCount, 1)
        XCTAssertNil(viewModel.runningMode)
        XCTAssertNil(viewModel.activeObservationSessionId)
        XCTAssertEqual(viewModel.capturedEventCount, 0)
    }

    func testTeachingModeStartFailsWhenDataDirectoryIsNotWritable() {
        let capture = FakeModeObservationCaptureService()
        let viewModel = OpenStaffDashboardViewModel(
            modeObservationCapture: capture,
            permissionSnapshotProvider: { _ in
                PermissionSnapshot(accessibilityTrusted: true, dataDirectoryWritable: false)
            }
        )

        viewModel.startMode(.teaching)

        XCTAssertEqual(capture.startCallCount, 0)
        XCTAssertNil(viewModel.runningMode)
        XCTAssertTrue(viewModel.transitionMessage?.contains("数据目录不可写") == true)
    }

    private func waitForMainQueue() {
        let expectation = expectation(description: "main queue drain")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
}

private final class FakeModeObservationCaptureService: ModeObservationCaptureControlling {
    var onFatalError: ((Error) -> Void)?
    var onEventCaptured: ((Int) -> Void)?

    private(set) var isRunning = false
    private(set) var capturedEventCount = 0
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastSessionId: String?
    private(set) var lastIncludeWindowContext: Bool?

    func start(sessionId: String, includeWindowContext: Bool) throws {
        isRunning = true
        startCallCount += 1
        lastSessionId = sessionId
        lastIncludeWindowContext = includeWindowContext
        capturedEventCount = 0
        onEventCaptured?(capturedEventCount)
    }

    func stop() {
        isRunning = false
        stopCallCount += 1
        capturedEventCount = 0
        onEventCaptured?(capturedEventCount)
    }

    func emitCapturedCount(_ count: Int) {
        capturedEventCount = count
        onEventCaptured?(count)
    }
}
