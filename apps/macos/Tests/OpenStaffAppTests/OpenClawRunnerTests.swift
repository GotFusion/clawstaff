import Foundation
import XCTest
import OpenStaffOpenClawCLI

final class OpenClawRunnerTests: XCTestCase {
    func testRunnerRejectsRequestWhenSemanticOnlyIsDisabled() throws {
        let logsRoot = try makeTemporaryDirectory()
        let runner = OpenClawRunner(
            subprocessRunner: FailingSubprocessRunner(),
            nowProvider: { Date(timeIntervalSince1970: 1_774_000_000) }
        )

        let result = runner.execute(
            request: makeRequest(
                logsRoot: logsRoot,
                runtimeArguments: ["--gateway-mode", "--json-result"],
                semanticOnly: false
            )
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.errorCode, OpenClawExecutionErrorCode.semanticOnlyRequired.rawValue)
        XCTAssertTrue(result.summary.contains("semantic_only=true"))
    }

    func testRunnerAllowsGatewayArgumentsWithoutSemanticOnlyFlagAfterCutover() throws {
        let logsRoot = try makeTemporaryDirectory()
        let subprocessRunner = CapturingSubprocessRunner(output: try makeSucceededGatewayOutput())
        let runner = OpenClawRunner(
            subprocessRunner: subprocessRunner,
            nowProvider: { Date(timeIntervalSince1970: 1_774_000_000) }
        )

        let result = runner.execute(
            request: makeRequest(
                logsRoot: logsRoot,
                runtimeArguments: ["--gateway-mode", "--json-result"],
                semanticOnly: true
            )
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertNil(result.errorCode)
        XCTAssertEqual(subprocessRunner.requests.count, 1)
        XCTAssertFalse(subprocessRunner.requests[0].runtimeArguments.contains("--semantic-only"))
    }

    private func makeRequest(
        logsRoot: URL,
        runtimeArguments: [String],
        semanticOnly: Bool
    ) -> OpenClawExecutionRequest {
        OpenClawExecutionRequest(
            traceId: "trace-openclaw-runner-test",
            sessionId: "session-openclaw-runner-test",
            taskId: "task-openclaw-runner-test",
            skillName: "skill-openclaw-runner-test",
            skillDirectoryPath: sampleSkillDirectory().path,
            runtimeExecutablePath: "/bin/echo",
            runtimeArguments: runtimeArguments,
            logsRootDirectoryPath: logsRoot.path,
            semanticOnly: semanticOnly,
            teacherConfirmed: true
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("openstaff-openclaw-runner-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func sampleSkillDirectory() -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repositoryRoot
            .appendingPathComponent("scripts/skills/examples/generated/openstaff-task-session-20260307-a1-001", isDirectory: true)
    }

    private func makeSucceededGatewayOutput() throws -> OpenClawSubprocessOutput {
        let payload = OpenClawGatewayExecutionPayload(
            traceId: "trace-openclaw-runner-test",
            sessionId: "session-openclaw-runner-test",
            taskId: "task-openclaw-runner-test",
            skillName: "skill-openclaw-runner-test",
            skillDirectoryPath: sampleSkillDirectory().path,
            status: .succeeded,
            startedAt: "2026-03-28T10:00:00.000Z",
            finishedAt: "2026-03-28T10:00:01.000Z",
            summary: "Gateway finished skill skill-openclaw-runner-test. total=1 succeeded=1 failed=0 blocked=0",
            totalSteps: 1,
            succeededSteps: 1,
            failedSteps: 0,
            blockedSteps: 0,
            stepResults: [
                OpenClawExecutionStepResult(
                    stepId: "step-001",
                    actionType: "click",
                    status: .succeeded,
                    startedAt: "2026-03-28T10:00:00.100Z",
                    finishedAt: "2026-03-28T10:00:00.900Z",
                    output: "Gateway executed click -> button:Open"
                )
            ]
        )
        let data = try JSONEncoder().encode(payload)
        let stdout = String(data: data, encoding: .utf8) ?? "{}"
        return OpenClawSubprocessOutput(exitCode: 0, stdout: stdout, stderr: "")
    }
}

private struct FailingSubprocessRunner: OpenClawSubprocessRunning {
    func run(request: OpenClawExecutionRequest) throws -> OpenClawSubprocessOutput {
        XCTFail("Subprocess runner should not be invoked for invalid semantic execution requests.")
        return OpenClawSubprocessOutput(exitCode: 1, stdout: "", stderr: "")
    }
}

private final class CapturingSubprocessRunner: OpenClawSubprocessRunning {
    private(set) var requests: [OpenClawExecutionRequest] = []
    private let output: OpenClawSubprocessOutput

    init(output: OpenClawSubprocessOutput) {
        self.output = output
    }

    func run(request: OpenClawExecutionRequest) throws -> OpenClawSubprocessOutput {
        requests.append(request)
        return output
    }
}
