import AppKit
import ApplicationServices
import Foundation

struct FrontmostContextResolver {
    func snapshot() -> ContextSnapshot {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return ContextSnapshot(
                appName: "Unknown",
                appBundleId: "unknown.bundle.id",
                windowTitle: nil,
                windowId: nil,
                isFrontmost: true
            )
        }

        let pid = app.processIdentifier
        return ContextSnapshot(
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
        let result = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleValue)
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

        guard result == .success, let focusedWindowValue else {
            return nil
        }

        return (focusedWindowValue as! AXUIElement)
    }
}
