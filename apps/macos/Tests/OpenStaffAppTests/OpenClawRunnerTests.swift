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

    func testRunnerRejectsLegacyGatewayArgumentsWithoutSemanticOnlyFlag() throws {
        let logsRoot = try makeTemporaryDirectory()
        let runner = OpenClawRunner(
            subprocessRunner: FailingSubprocessRunner(),
            nowProvider: { Date(timeIntervalSince1970: 1_774_000_000) }
        )

        let result = runner.execute(
            request: makeRequest(
                logsRoot: logsRoot,
                runtimeArguments: ["--gateway-mode", "--json-result"],
                semanticOnly: true
            )
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.errorCode, OpenClawExecutionErrorCode.semanticOnlyRequired.rawValue)
        XCTAssertTrue(result.summary.contains("--semantic-only"))
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
            skillDirectoryPath: "/tmp/skill-openclaw-runner-test",
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
}

private struct FailingSubprocessRunner: OpenClawSubprocessRunning {
    func run(request: OpenClawExecutionRequest) throws -> OpenClawSubprocessOutput {
        XCTFail("Subprocess runner should not be invoked for invalid semantic execution requests.")
        return OpenClawSubprocessOutput(exitCode: 1, stdout: "", stderr: "")
    }
}
