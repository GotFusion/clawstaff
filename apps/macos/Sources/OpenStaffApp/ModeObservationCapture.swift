import AppKit
import ApplicationServices
import Foundation

enum DashboardCaptureStartupError: LocalizedError {
    case accessibilityPermissionDenied(executablePath: String)
    case dataDirectoryNotWritable(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied(let executablePath):
            return "缺少辅助功能权限，无法监控全局点击。请在 系统设置 > 隐私与安全性 > 辅助功能 中允许此可执行文件：\(executablePath)"
        case .dataDirectoryNotWritable(let path):
            return "数据目录不可写：\(path)"
        }
    }
}

protocol ModeObservationCaptureControlling: AnyObject {
    var isRunning: Bool { get }
    var capturedEventCount: Int { get }
    var onFatalError: ((Error) -> Void)? { get set }
    var onEventCaptured: ((Int) -> Void)? { get set }

    func start(sessionId: String, includeWindowContext: Bool) throws
    func stop()
}

final class ModeObservationCaptureService: ModeObservationCaptureControlling {
    var onFatalError: ((Error) -> Void)?
    var onEventCaptured: ((Int) -> Void)?

    private let outputRootDirectory: URL
    private let contextResolver = ModeObservationContextResolver()
    private let timestampFormatter: ISO8601DateFormatter

    private var monitorToken: Any?
    private var eventSink: ModeObservationEventSink?
    private var capturedEventCountStorage = 0
    private var includeWindowContext = true

    init(outputRootDirectory: URL = OpenStaffWorkspacePaths.rawEventsDirectory) {
        self.outputRootDirectory = outputRootDirectory

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestampFormatter = formatter
    }

    var isRunning: Bool {
        monitorToken != nil
    }

    var capturedEventCount: Int {
        capturedEventCountStorage
    }

    func start(sessionId: String, includeWindowContext: Bool = true) throws {
        guard !isRunning else {
            throw ModeObservationCaptureError.alreadyRunning
        }
        guard ModeObservationCaptureService.isValidSessionId(sessionId) else {
            throw ModeObservationCaptureError.invalidSessionId(sessionId)
        }

        let sink = try ModeObservationEventSink(
            sessionId: sessionId,
            outputRootDirectory: outputRootDirectory
        )

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        guard let monitorToken = NSEvent.addGlobalMonitorForEvents(
            matching: mask,
            handler: { [weak self] event in
                self?.handleEvent(event, sessionId: sessionId)
            }
        ) else {
            try? sink.close()
            throw ModeObservationCaptureError.globalMonitorUnavailable
        }

        self.eventSink = sink
        self.monitorToken = monitorToken
        self.capturedEventCountStorage = 0
        self.includeWindowContext = includeWindowContext
        onEventCaptured?(capturedEventCountStorage)
    }

    func stop() {
        stop(reportCloseError: true)
    }

    private func stop(reportCloseError: Bool) {
        if let monitorToken {
            NSEvent.removeMonitor(monitorToken)
            self.monitorToken = nil
        }

        if let eventSink {
            do {
                try eventSink.close()
            } catch {
                if reportCloseError {
                    onFatalError?(ModeObservationCaptureError.storageCloseFailed(error))
                }
            }
        }

        self.eventSink = nil
        self.capturedEventCountStorage = 0
        self.includeWindowContext = true
        onEventCaptured?(capturedEventCountStorage)
    }

    private func handleEvent(_ event: NSEvent, sessionId: String) {
        guard let action = mapAction(event) else {
            return
        }
        guard let eventSink else {
            return
        }

        let rawEvent = ModeObservationRawEvent(
            eventId: UUID().uuidString.lowercased(),
            sessionId: sessionId,
            timestamp: timestampFormatter.string(from: Date()),
            action: action,
            pointer: ModeObservationPointer(
                x: Int(event.locationInWindow.x.rounded()),
                y: Int(event.locationInWindow.y.rounded())
            ),
            contextSnapshot: contextResolver.snapshot(includeWindowContext: includeWindowContext),
            modifiers: keyboardModifiers(from: event)
        )

        do {
            try eventSink.append(rawEvent)
            capturedEventCountStorage += 1
            onEventCaptured?(capturedEventCountStorage)
        } catch {
            stop(reportCloseError: false)
            onFatalError?(ModeObservationCaptureError.storageWriteFailed(error))
        }
    }

    private func mapAction(_ event: NSEvent) -> ModeObservationAction? {
        switch event.type {
        case .leftMouseDown:
            return event.clickCount >= 2 ? .doubleClick : .leftClick
        case .rightMouseDown:
            return .rightClick
        default:
            return nil
        }
    }

    private func keyboardModifiers(from event: NSEvent) -> [ModeObservationModifier] {
        var modifiers: [ModeObservationModifier] = []

        if event.modifierFlags.contains(.command) {
            modifiers.append(.command)
        }
        if event.modifierFlags.contains(.shift) {
            modifiers.append(.shift)
        }
        if event.modifierFlags.contains(.option) {
            modifiers.append(.option)
        }
        if event.modifierFlags.contains(.control) {
            modifiers.append(.control)
        }

        return modifiers
    }

    private static func isValidSessionId(_ value: String) -> Bool {
        let pattern = "^[a-z0-9-]+$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}

private final class ModeObservationEventSink {
    private let fileHandle: FileHandle
    private let encoder = JSONEncoder()
    private let lock = NSLock()

    init(
        sessionId: String,
        outputRootDirectory: URL,
        nowProvider: () -> Date = Date.init
    ) throws {
        let fileManager = FileManager.default
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dayDirectory = outputRootDirectory.appendingPathComponent(
            dateFormatter.string(from: nowProvider()),
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(
                at: dayDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw ModeObservationSinkError.createDirectoryFailed(dayDirectory.path, error)
        }

        let fileURL = dayDirectory.appendingPathComponent("\(sessionId).jsonl", isDirectory: false)
        if !fileManager.fileExists(atPath: fileURL.path) {
            let created = fileManager.createFile(atPath: fileURL.path, contents: nil)
            if !created {
                throw ModeObservationSinkError.createFileFailed(fileURL.path)
            }
        }

        do {
            fileHandle = try FileHandle(forUpdating: fileURL)
            _ = try fileHandle.seekToEnd()
        } catch {
            throw ModeObservationSinkError.openFileFailed(fileURL.path, error)
        }
    }

    func append(_ event: ModeObservationRawEvent) throws {
        let lineData: Data
        do {
            lineData = try encodeJSONLine(event)
        } catch {
            throw ModeObservationSinkError.encodeFailed(error)
        }

        lock.lock()
        defer { lock.unlock() }
        do {
            try fileHandle.write(contentsOf: lineData)
        } catch {
            throw ModeObservationSinkError.writeFailed(error)
        }
    }

    func close() throws {
        lock.lock()
        defer { lock.unlock() }
        do {
            try fileHandle.close()
        } catch {
            throw ModeObservationSinkError.closeFailed(error)
        }
    }

    private func encodeJSONLine(_ event: ModeObservationRawEvent) throws -> Data {
        var data = try encoder.encode(event)
        data.append(0x0A)
        return data
    }
}

private struct ModeObservationContextResolver {
    func snapshot(includeWindowContext: Bool) -> ModeObservationContextSnapshot {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return ModeObservationContextSnapshot(
                appName: "Unknown",
                appBundleId: "unknown.bundle.id",
                windowTitle: nil,
                windowId: nil,
                isFrontmost: true
            )
        }

        let pid = app.processIdentifier
        if !includeWindowContext {
            return ModeObservationContextSnapshot(
                appName: app.localizedName ?? "Unknown",
                appBundleId: app.bundleIdentifier ?? "unknown.bundle.id",
                windowTitle: nil,
                windowId: nil,
                isFrontmost: true
            )
        }

        return ModeObservationContextSnapshot(
            appName: app.localizedName ?? "Unknown",
            appBundleId: app.bundleIdentifier ?? "unknown.bundle.id",
            windowTitle: focusedWindowTitle(pid: pid),
            windowId: focusedWindowId(pid: pid),
            isFrontmost: true
        )
    }

    private func focusedWindowTitle(pid: pid_t) -> String? {
        guard let windowElement = focusedWindowElement(pid: pid) else {
            return nil
        }

        var titleValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            windowElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )
        guard result == .success else {
            return nil
        }

        return titleValue as? String
    }

    private func focusedWindowId(pid: pid_t) -> String? {
        guard let windowElement = focusedWindowElement(pid: pid) else {
            return nil
        }

        var idValue: CFTypeRef?
        let attribute = "AXWindowNumber" as CFString
        let result = AXUIElementCopyAttributeValue(windowElement, attribute, &idValue)
        guard result == .success else {
            return nil
        }

        if let number = idValue as? NSNumber {
            return number.stringValue
        }
        return idValue as? String
    }

    private func focusedWindowElement(pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindowValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )
        guard result == .success else {
            return nil
        }

        return (focusedWindowValue as! AXUIElement)
    }
}

private struct ModeObservationRawEvent: Codable {
    let schemaVersion: String
    let eventId: String
    let sessionId: String
    let timestamp: String
    let source: ModeObservationSource
    let action: ModeObservationAction
    let pointer: ModeObservationPointer
    let contextSnapshot: ModeObservationContextSnapshot
    let modifiers: [ModeObservationModifier]

    init(
        eventId: String,
        sessionId: String,
        timestamp: String,
        action: ModeObservationAction,
        pointer: ModeObservationPointer,
        contextSnapshot: ModeObservationContextSnapshot,
        modifiers: [ModeObservationModifier]
    ) {
        self.schemaVersion = "capture.raw.v0"
        self.eventId = eventId
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.source = .mouse
        self.action = action
        self.pointer = pointer
        self.contextSnapshot = contextSnapshot
        self.modifiers = modifiers
    }
}

private enum ModeObservationSource: String, Codable {
    case mouse
}

private enum ModeObservationAction: String, Codable {
    case leftClick
    case rightClick
    case doubleClick
}

private enum ModeObservationModifier: String, Codable {
    case command
    case shift
    case option
    case control
}

private struct ModeObservationPointer: Codable {
    let x: Int
    let y: Int
    let coordinateSpace: String

    init(x: Int, y: Int, coordinateSpace: String = "screen") {
        self.x = x
        self.y = y
        self.coordinateSpace = coordinateSpace
    }
}

private struct ModeObservationContextSnapshot: Codable {
    let appName: String
    let appBundleId: String
    let windowTitle: String?
    let windowId: String?
    let isFrontmost: Bool
}

private enum ModeObservationCaptureError: LocalizedError {
    case alreadyRunning
    case invalidSessionId(String)
    case globalMonitorUnavailable
    case storageWriteFailed(Error)
    case storageCloseFailed(Error)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "监控服务已在运行。"
        case .invalidSessionId(let sessionId):
            return "sessionId 不合法：\(sessionId)"
        case .globalMonitorUnavailable:
            return "无法启动全局鼠标事件监听。"
        case .storageWriteFailed(let error):
            return "写入采集事件失败：\(error.localizedDescription)"
        case .storageCloseFailed(let error):
            return "关闭采集写入器失败：\(error.localizedDescription)"
        }
    }
}

private enum ModeObservationSinkError: LocalizedError {
    case createDirectoryFailed(String, Error)
    case createFileFailed(String)
    case openFileFailed(String, Error)
    case encodeFailed(Error)
    case writeFailed(Error)
    case closeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .createDirectoryFailed(let path, let error):
            return "创建目录失败（\(path)）：\(error.localizedDescription)"
        case .createFileFailed(let path):
            return "创建文件失败：\(path)"
        case .openFileFailed(let path, let error):
            return "打开文件失败（\(path)）：\(error.localizedDescription)"
        case .encodeFailed(let error):
            return "编码采集事件失败：\(error.localizedDescription)"
        case .writeFailed(let error):
            return "写入采集事件失败：\(error.localizedDescription)"
        case .closeFailed(let error):
            return "关闭采集文件失败：\(error.localizedDescription)"
        }
    }
}
