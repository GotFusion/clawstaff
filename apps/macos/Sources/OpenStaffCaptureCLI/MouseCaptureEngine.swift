import AppKit
import Foundation

final class MouseCaptureEngine {
    private let sessionId: String
    private let maxEvents: Int?
    private let printJSON: Bool
    private let queue: RawEventQueue
    private let contextResolver: FrontmostContextResolver
    private let timestampFormatter: ISO8601DateFormatter

    private var monitorToken: Any?
    private let encoder = JSONEncoder()

    var onStopRequested: (() -> Void)?

    init(
        sessionId: String,
        maxEvents: Int?,
        printJSON: Bool,
        queue: RawEventQueue = RawEventQueue(),
        contextResolver: FrontmostContextResolver = FrontmostContextResolver()
    ) {
        self.sessionId = sessionId
        self.maxEvents = maxEvents
        self.printJSON = printJSON
        self.queue = queue
        self.contextResolver = contextResolver

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestampFormatter = formatter
    }

    var capturedCount: Int {
        queue.count
    }

    func start() throws {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        guard let monitorToken = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handleEvent(_:)) else {
            throw CaptureEngineError.globalMonitorUnavailable
        }

        self.monitorToken = monitorToken
    }

    func stop() {
        guard let monitorToken else {
            return
        }

        NSEvent.removeMonitor(monitorToken)
        self.monitorToken = nil
    }

    private func handleEvent(_ event: NSEvent) {
        guard let action = mapAction(event) else {
            return
        }

        let rawEvent = RawEvent(
            eventId: UUID().uuidString.lowercased(),
            sessionId: sessionId,
            timestamp: timestampFormatter.string(from: Date()),
            source: .mouse,
            action: action,
            pointer: PointerLocation(
                x: Int(event.locationInWindow.x.rounded()),
                y: Int(event.locationInWindow.y.rounded())
            ),
            contextSnapshot: contextResolver.snapshot(),
            modifiers: keyboardModifiers(from: event)
        )

        let count = queue.enqueue(rawEvent)

        if printJSON {
            if let line = encodeJSONLine(rawEvent) {
                print(line)
            }
        } else {
            let windowTitle = rawEvent.contextSnapshot.windowTitle ?? "<no-window-title>"
            print("[captured=\(count)] \(rawEvent.action.rawValue) app=\(rawEvent.contextSnapshot.appName) window=\(windowTitle) point=(\(rawEvent.pointer.x),\(rawEvent.pointer.y))")
        }

        if let maxEvents, count >= maxEvents {
            onStopRequested?()
        }
    }

    private func mapAction(_ event: NSEvent) -> RawEventAction? {
        switch event.type {
        case .leftMouseDown:
            return event.clickCount >= 2 ? .doubleClick : .leftClick
        case .rightMouseDown:
            return .rightClick
        default:
            return nil
        }
    }

    private func keyboardModifiers(from event: NSEvent) -> [KeyboardModifier] {
        var modifiers: [KeyboardModifier] = []

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

    private func encodeJSONLine(_ event: RawEvent) -> String? {
        guard let data = try? encoder.encode(event) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}

enum CaptureEngineError: LocalizedError {
    case globalMonitorUnavailable

    var errorDescription: String? {
        switch self {
        case .globalMonitorUnavailable:
            return "Failed to start global mouse monitor."
        }
    }
}
