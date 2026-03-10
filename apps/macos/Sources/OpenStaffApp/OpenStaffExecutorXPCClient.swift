import Foundation
import CoreGraphics
import OpenStaffExecutorShared

final class OpenStaffExecutorXPCClient: @unchecked Sendable {
    static let shared = OpenStaffExecutorXPCClient()

    private let lock = NSLock()
    private var helperProcess: Process?
    private var connection: NSXPCConnection?
    private var endpointFileURL: URL?
    private var helperExecutablePath: String?
    private var preferOneShotExecution = true

    private init() {}

    func executeAction(
        actionType: String,
        target: String,
        instruction: String,
        contextBundleId: String,
        fallbackCoordinate: CGPoint?
    ) -> LearnedSkillActionResult {
        let request = NSMutableDictionary()
        request[OpenStaffExecutorIPCKeys.actionType] = actionType
        request[OpenStaffExecutorIPCKeys.target] = target
        request[OpenStaffExecutorIPCKeys.instruction] = instruction
        request[OpenStaffExecutorIPCKeys.contextBundleId] = contextBundleId
        if let fallbackCoordinate {
            request[OpenStaffExecutorIPCKeys.fallbackX] = NSNumber(value: Double(fallbackCoordinate.x))
            request[OpenStaffExecutorIPCKeys.fallbackY] = NSNumber(value: Double(fallbackCoordinate.y))
        }

        if shouldPreferOneShotExecution() {
            return executeActionViaOneShotHelper(request)
        }

        let proxy: OpenStaffExecutorXPCProtocol
        do {
            proxy = try connectedProxy()
        } catch {
            markPreferOneShotExecution()
            return executeActionViaOneShotHelper(request)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var finished = false
        var result: LearnedSkillActionResult = .failed("OpenStaffExecutor 未返回结果。")

        let remoteProxy = connection?.remoteObjectProxyWithErrorHandler { error in
            self.lock.lock()
            defer { self.lock.unlock() }
            guard !finished else {
                return
            }
            finished = true
            result = .failed("OpenStaffExecutor 连接错误：\(error.localizedDescription)")
            semaphore.signal()
        } as? OpenStaffExecutorXPCProtocol ?? proxy

        remoteProxy.execute(request) { reply in
            self.lock.lock()
            defer { self.lock.unlock() }
            guard !finished else {
                return
            }
            finished = true
            result = Self.mapReply(reply)
            semaphore.signal()
        }

        let timeout = DispatchTime.now() + .seconds(12)
        if semaphore.wait(timeout: timeout) == .timedOut {
            markPreferOneShotExecution()
            invalidateConnection()
            return executeActionViaOneShotHelper(request)
        }
        return result
    }

    func currentHelperExecutablePath() -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let helperExecutablePath {
            return helperExecutablePath
        }
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["OPENSTAFF_EXECUTOR_HELPER_PATH"] {
            let normalized = override.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                return normalized
            }
        }
        let managedURL = managedHelperExecutableURL()
        if FileManager.default.isExecutableFile(atPath: managedURL.path) {
            return managedURL.path
        }
        if let discovered = firstExecutableCandidate(in: helperExecutableCandidates()) {
            return discovered.path
        }
        return nil
    }

    private func connectedProxy() throws -> OpenStaffExecutorXPCProtocol {
        let connection = try ensureConnection()
        let proxyAny = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
            self?.invalidateConnection()
        }
        guard let proxy = proxyAny as? OpenStaffExecutorXPCProtocol else {
            throw OpenStaffExecutorXPCClientError.remoteProxyUnavailable
        }
        return proxy
    }

    private func ensureConnection() throws -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }

        if let connection {
            return connection
        }

        let endpointURL = helperEndpointURL()
        let helperURL = try resolveHelperExecutableURL()
        try? FileManager.default.removeItem(at: endpointURL)

        let process = Process()
        process.executableURL = helperURL
        process.arguments = ["--endpoint-file", endpointURL.path]
        process.currentDirectoryURL = OpenStaffWorkspacePaths.repositoryRoot

        do {
            try process.run()
        } catch {
            throw OpenStaffExecutorXPCClientError.helperLaunchFailed(helperURL.path)
        }

        let endpoint = try waitAndLoadEndpoint(from: endpointURL)
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: OpenStaffExecutorXPCProtocol.self)
        connection.interruptionHandler = { [weak self] in
            self?.invalidateConnection()
        }
        connection.invalidationHandler = { [weak self] in
            self?.invalidateConnection()
        }
        connection.resume()

        self.helperProcess = process
        self.endpointFileURL = endpointURL
        self.connection = connection
        self.helperExecutablePath = helperURL.path
        return connection
    }

    private func shouldPreferOneShotExecution() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return preferOneShotExecution
    }

    private func markPreferOneShotExecution() {
        lock.lock()
        defer { lock.unlock() }
        preferOneShotExecution = true
    }

    private func invalidateConnection() {
        lock.lock()
        defer { lock.unlock() }
        connection?.invalidate()
        connection = nil
        if let helperProcess, helperProcess.isRunning {
            helperProcess.terminate()
        }
        self.helperProcess = nil
        if let endpointFileURL {
            try? FileManager.default.removeItem(at: endpointFileURL)
        }
        endpointFileURL = nil
    }

    private func helperEndpointURL() -> URL {
        let runtimeDirectory = OpenStaffWorkspacePaths.runtimeDirectory
            .appendingPathComponent("openstaff-executor", isDirectory: true)
        try? FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        return runtimeDirectory.appendingPathComponent("xpc-endpoint.data", isDirectory: false)
    }

    private func waitAndLoadEndpoint(from endpointURL: URL) throws -> NSXPCListenerEndpoint {
        let deadline = Date().addingTimeInterval(8.0)
        let fileManager = FileManager.default
        while Date() < deadline {
            if fileManager.fileExists(atPath: endpointURL.path),
               let data = try? Data(contentsOf: endpointURL),
               let endpoint = try? NSKeyedUnarchiver.unarchivedObject(
                   ofClass: NSXPCListenerEndpoint.self,
                   from: data
               ) {
                return endpoint
            }
            if fileManager.fileExists(atPath: endpointURL.path),
               let data = try? Data(contentsOf: endpointURL),
               let endpoint = NSKeyedUnarchiver.unarchiveObject(with: data) as? NSXPCListenerEndpoint {
                return endpoint
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw OpenStaffExecutorXPCClientError.endpointUnavailable(endpointURL.path)
    }

    private func resolveHelperExecutableURL() throws -> URL {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        let managedHelperURL = managedHelperExecutableURL()

        if let override = environment["OPENSTAFF_EXECUTOR_HELPER_PATH"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: false)
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
            // Compatibility fallback: legacy scheme/env may point to a stale path.
            // If override is invalid, continue with managed/built candidates.
        }

        // Prefer syncing from latest build output so managed helper stays up-to-date.
        let initialCandidates = helperExecutableCandidates()
        if let candidate = firstExecutableCandidate(in: initialCandidates) {
            try? syncHelperExecutable(from: candidate, to: managedHelperURL)
            if fileManager.isExecutableFile(atPath: managedHelperURL.path) {
                return managedHelperURL
            }
            return candidate
        }

        if fileManager.isExecutableFile(atPath: managedHelperURL.path) {
            return managedHelperURL
        }

        try buildHelperProduct()
        let rebuiltCandidates = helperExecutableCandidates()
        if let candidate = firstExecutableCandidate(in: rebuiltCandidates) {
            try? syncHelperExecutable(from: candidate, to: managedHelperURL)
            if fileManager.isExecutableFile(atPath: managedHelperURL.path) {
                return managedHelperURL
            }
            return candidate
        }

        throw OpenStaffExecutorXPCClientError.helperMissing(managedHelperURL.path)
    }

    private func helperExecutableCandidates() -> [URL] {
        var candidates: [URL] = []

        if let currentExecutablePath = ProcessInfo.processInfo.arguments.first,
           !currentExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let currentExecutableDirectory = URL(fileURLWithPath: currentExecutablePath, isDirectory: false)
                .deletingLastPathComponent()
            candidates.append(currentExecutableDirectory.appendingPathComponent("OpenStaffExecutorHelper", isDirectory: false))
        }

        let buildRoot = OpenStaffWorkspacePaths.repositoryRoot
            .appendingPathComponent("apps/macos/.build", isDirectory: true)
        candidates.append(buildRoot.appendingPathComponent("debug/OpenStaffExecutorHelper", isDirectory: false))
        candidates.append(buildRoot.appendingPathComponent("arm64-apple-macosx/debug/OpenStaffExecutorHelper", isDirectory: false))
        candidates.append(buildRoot.appendingPathComponent("x86_64-apple-macosx/debug/OpenStaffExecutorHelper", isDirectory: false))

        if let discovered = discoverHelperUnderBuildRoot(buildRoot) {
            candidates.append(discovered)
        }
        return candidates
    }

    private func firstExecutableCandidate(in candidates: [URL]) -> URL? {
        let fileManager = FileManager.default
        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    private func managedHelperExecutableURL() -> URL {
        let helperDirectory = OpenStaffWorkspacePaths.runtimeDirectory
            .appendingPathComponent("openstaff-executor", isDirectory: true)
        try? FileManager.default.createDirectory(at: helperDirectory, withIntermediateDirectories: true)
        return helperDirectory.appendingPathComponent("OpenStaffExecutorHelper", isDirectory: false)
    }

    private func syncHelperExecutable(from sourceURL: URL, to destinationURL: URL) throws {
        if sourceURL.standardizedFileURL.path == destinationURL.standardizedFileURL.path {
            return
        }

        let fileManager = FileManager.default
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: destinationURL.path
        )
    }

    private func discoverHelperUnderBuildRoot(_ buildRoot: URL) -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: buildRoot.path),
              let enumerator = fileManager.enumerator(
                  at: buildRoot,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return nil
        }

        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "OpenStaffExecutorHelper" {
            if fileManager.isExecutableFile(atPath: fileURL.path) {
                return fileURL
            }
        }
        return nil
    }

    private func buildHelperProduct() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swift",
            "build",
            "--package-path",
            OpenStaffWorkspacePaths.repositoryRoot
                .appendingPathComponent("apps/macos", isDirectory: true)
                .path,
            "--product",
            "OpenStaffExecutorHelper"
        ]
        process.currentDirectoryURL = OpenStaffWorkspacePaths.repositoryRoot

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw OpenStaffExecutorXPCClientError.helperBuildFailed("无法启动 swift build。")
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? "unknown"
            throw OpenStaffExecutorXPCClientError.helperBuildFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func mapReply(_ reply: NSDictionary) -> LearnedSkillActionResult {
        let success = (reply[OpenStaffExecutorIPCKeys.success] as? NSNumber)?.boolValue ?? false
        let blocked = (reply[OpenStaffExecutorIPCKeys.blocked] as? NSNumber)?.boolValue ?? false
        let message = (reply[OpenStaffExecutorIPCKeys.message] as? String) ?? "OpenStaffExecutor 返回空消息。"

        if success {
            return .succeeded(message)
        }
        if blocked {
            return .blocked(message)
        }
        return .failed(message)
    }

    private func executeActionViaOneShotHelper(_ request: NSDictionary) -> LearnedSkillActionResult {
        let helperURL: URL
        do {
            helperURL = try resolveHelperExecutableURL()
        } catch {
            return .failed("OpenStaffExecutor 不可用：\(error.localizedDescription)")
        }

        lock.lock()
        helperExecutablePath = helperURL.path
        lock.unlock()

        let process = Process()
        process.executableURL = helperURL
        process.arguments = ["--oneshot-json-stdin"]
        process.currentDirectoryURL = OpenStaffWorkspacePaths.repositoryRoot

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .failed("OpenStaffExecutor one-shot 启动失败：\(error.localizedDescription)")
        }

        do {
            let payloadData = try JSONSerialization.data(withJSONObject: request, options: [])
            stdinPipe.fileHandleForWriting.write(payloadData)
            try stdinPipe.fileHandleForWriting.close()
        } catch {
            process.terminate()
            return .failed("OpenStaffExecutor one-shot 请求编码失败：\(error.localizedDescription)")
        }

        process.waitUntilExit()

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            if !stderrText.isEmpty {
                return .failed("OpenStaffExecutor one-shot 执行失败：\(stderrText)")
            }
            return .failed("OpenStaffExecutor one-shot 执行失败（exit=\(process.terminationStatus)）。")
        }

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard !outputData.isEmpty else {
            return .failed("OpenStaffExecutor one-shot 未返回结果。")
        }

        guard let payload = try? JSONSerialization.jsonObject(with: outputData, options: []),
              let reply = payload as? NSDictionary else {
            if !stderrText.isEmpty {
                return .failed("OpenStaffExecutor one-shot 返回数据不可解析：\(stderrText)")
            }
            return .failed("OpenStaffExecutor one-shot 返回数据不可解析。")
        }
        return Self.mapReply(reply)
    }
}

enum OpenStaffExecutorXPCClientError: LocalizedError {
    case helperMissing(String)
    case helperLaunchFailed(String)
    case endpointUnavailable(String)
    case helperBuildFailed(String)
    case remoteProxyUnavailable

    var errorDescription: String? {
        switch self {
        case .helperMissing(let path):
            return "未找到 OpenStaffExecutorHelper：\(path)"
        case .helperLaunchFailed(let path):
            return "启动 OpenStaffExecutorHelper 失败：\(path)"
        case .endpointUnavailable(let path):
            return "无法读取 XPC endpoint 文件：\(path)"
        case .helperBuildFailed(let message):
            return "自动编译 OpenStaffExecutorHelper 失败：\(message)"
        case .remoteProxyUnavailable:
            return "XPC remote proxy 不可用。"
        }
    }
}
