import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum OpenStaffActionExecutionBackend: String {
    case app
    case helper

    var displayName: String {
        switch self {
        case .app:
            return "OpenStaffApp（仅需 OpenStaffApp 辅助功能权限）"
        case .helper:
            return "OpenStaffExecutorHelper（需要 helper 辅助功能权限）"
        }
    }
}

enum OpenStaffActionExecutor {
    static var backend: OpenStaffActionExecutionBackend {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["OPENSTAFF_EXECUTOR_BACKEND"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           override == OpenStaffActionExecutionBackend.helper.rawValue {
            return .helper
        }
        return .app
    }

    static var usesHelperBackend: Bool {
        backend == .helper
    }

    static func executeAction(
        actionType: String,
        target: String,
        instruction: String,
        contextBundleId: String,
        fallbackCoordinate: CGPoint?
    ) -> LearnedSkillActionResult {
        switch backend {
        case .app:
            return executeActionInAppProcess(
                actionType: actionType,
                target: target,
                instruction: instruction,
                contextBundleId: contextBundleId,
                fallbackCoordinate: fallbackCoordinate
            )
        case .helper:
            return OpenStaffExecutorXPCClient.shared.executeAction(
                actionType: actionType,
                target: target,
                instruction: instruction,
                contextBundleId: contextBundleId,
                fallbackCoordinate: fallbackCoordinate
            )
        }
    }

    private static func executeActionInAppProcess(
        actionType: String,
        target: String,
        instruction: String,
        contextBundleId: String,
        fallbackCoordinate: CGPoint?
    ) -> LearnedSkillActionResult {
        switch actionType {
        case "click":
            return performClick(
                target: target,
                contextBundleId: contextBundleId,
                fallbackCoordinate: fallbackCoordinate
            )
        case "shortcut":
            return performShortcut(
                target: target,
                instruction: instruction,
                contextBundleId: contextBundleId
            )
        case "input":
            return performInput(
                target: target,
                instruction: instruction,
                contextBundleId: contextBundleId
            )
        case "openApp":
            return performOpenApp(target: target, contextBundleId: contextBundleId)
        case "wait":
            return performWait(target: target, instruction: instruction)
        default:
            return .failed("未知 actionType=\(actionType)")
        }
    }

    private static func performClick(
        target: String,
        contextBundleId: String,
        fallbackCoordinate: CGPoint?
    ) -> LearnedSkillActionResult {
        guard ensureAccessibilityPermissionIfNeeded() else {
            return .blocked("点击被拦截：OpenStaffApp 未获得辅助功能权限。")
        }

        if !contextBundleId.isEmpty,
           !activateApp(bundleId: contextBundleId) {
            return .failed("点击失败：无法将目标应用置前（\(contextBundleId)）。")
        }

        guard let coordinate = parseCoordinate(from: target) ?? fallbackCoordinate else {
            return .failed("点击失败：缺少可用坐标。")
        }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(
                  mouseEventSource: source,
                  mouseType: .leftMouseDown,
                  mouseCursorPosition: coordinate,
                  mouseButton: .left
              ),
              let up = CGEvent(
                  mouseEventSource: source,
                  mouseType: .leftMouseUp,
                  mouseCursorPosition: coordinate,
                  mouseButton: .left
              ) else {
            return .failed("点击失败：无法创建鼠标事件。")
        }

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.08)
        return .succeeded("已执行 click：(\(Int(coordinate.x)), \(Int(coordinate.y)))")
    }

    private static func performShortcut(
        target: String,
        instruction: String,
        contextBundleId: String
    ) -> LearnedSkillActionResult {
        guard ensureAccessibilityPermissionIfNeeded() else {
            return .blocked("快捷键被拦截：OpenStaffApp 未获得辅助功能权限。")
        }

        if !contextBundleId.isEmpty,
           !activateApp(bundleId: contextBundleId) {
            return .failed("快捷键失败：无法将目标应用置前（\(contextBundleId)）。")
        }

        guard let shortcutSpec = parseShortcutSpec(target: target, instruction: instruction) else {
            return .failed("快捷键失败：无法从 target/instruction 解析快捷键。")
        }
        guard postShortcut(spec: shortcutSpec) else {
            return .failed("快捷键失败：无法发送键盘事件。")
        }
        return .succeeded("已执行 shortcut：\(shortcutSpec.raw)")
    }

    private static func performInput(
        target: String,
        instruction: String,
        contextBundleId: String
    ) -> LearnedSkillActionResult {
        guard ensureAccessibilityPermissionIfNeeded() else {
            return .blocked("输入被拦截：OpenStaffApp 未获得辅助功能权限。")
        }

        if !contextBundleId.isEmpty,
           !activateApp(bundleId: contextBundleId) {
            return .failed("输入失败：无法将目标应用置前（\(contextBundleId)）。")
        }

        guard let text = parseInputText(target: target, instruction: instruction),
              !text.isEmpty else {
            return .failed("输入失败：无法提取要输入的文本。")
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        guard let pasteShortcut = ShortcutSpec(raw: "command+v"),
              postShortcut(spec: pasteShortcut) else {
            return .failed("输入失败：无法发送粘贴快捷键。")
        }
        if shouldPressReturnAfterInput(target: target, instruction: instruction) {
            guard let returnShortcut = ShortcutSpec(raw: "return"),
                  postShortcut(spec: returnShortcut) else {
                return .failed("输入失败：文本已粘贴，但无法发送回车。")
            }
            return .succeeded("已执行 input：通过粘贴注入文本（\(text.count) chars）并回车")
        }
        return .succeeded("已执行 input：通过粘贴注入文本（\(text.count) chars）")
    }

    private static func performOpenApp(target: String, contextBundleId: String) -> LearnedSkillActionResult {
        let bundleId = parseBundleId(from: target) ?? contextBundleId
        if !bundleId.isEmpty {
            if activateApp(bundleId: bundleId) {
                return .succeeded("已执行 openApp：\(bundleId)")
            }
            return .failed("openApp 失败：无法启动或激活 \(bundleId)")
        }

        if let appName = parseAppName(from: target),
           let path = NSWorkspace.shared.fullPath(forApplication: appName) {
            let launched = NSWorkspace.shared.open(URL(fileURLWithPath: path))
            if launched {
                Thread.sleep(forTimeInterval: 0.30)
                return .succeeded("已执行 openApp：\(appName)")
            }
            return .failed("openApp 失败：无法按应用名启动 \(appName)")
        }

        return .failed("openApp 失败：缺少可解析的目标应用。")
    }

    private static func performWait(target: String, instruction: String) -> LearnedSkillActionResult {
        let seconds = parseWaitSeconds(target: target, instruction: instruction)
        Thread.sleep(forTimeInterval: seconds)
        return .succeeded("已执行 wait：\(String(format: "%.2f", seconds)) 秒")
    }

    private static func ensureAccessibilityPermissionIfNeeded() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return AXIsProcessTrusted()
    }

    private static func activateApp(bundleId: String) -> Bool {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier == bundleId {
            return true
        }

        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            let activated = running.activate(options: [.activateAllWindows])
            if activated {
                Thread.sleep(forTimeInterval: 0.25)
                return true
            }
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return false
        }
        let semaphore = DispatchSemaphore(value: 0)
        var opened = false
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
            opened = (app != nil && error == nil)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3.0)
        if opened {
            Thread.sleep(forTimeInterval: 0.30)
        }
        return opened
    }

    private static func parseCoordinate(from target: String) -> CGPoint? {
        guard target.hasPrefix("coordinate:") else {
            return nil
        }
        let raw = String(target.dropFirst("coordinate:".count))
        let parts = raw.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count == 2,
              let x = Double(parts[0]),
              let y = Double(parts[1]) else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    private static func parseBundleId(from target: String) -> String? {
        guard target.hasPrefix("bundle:") else {
            return nil
        }
        let value = String(target.dropFirst("bundle:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func parseAppName(from target: String) -> String? {
        guard target.hasPrefix("app:") else {
            return nil
        }
        let value = String(target.dropFirst("app:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func parseWaitSeconds(target: String, instruction: String) -> TimeInterval {
        if target.hasPrefix("seconds:") {
            let value = String(target.dropFirst("seconds:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let seconds = Double(value), seconds > 0 {
                return min(seconds, 10.0)
            }
        }

        let pattern = #"([0-9]+(?:\.[0-9]+)?)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(
               in: instruction,
               options: [],
               range: NSRange(location: 0, length: instruction.utf16.count)
           ),
           let range = Range(match.range(at: 1), in: instruction),
           let seconds = Double(instruction[range]),
           seconds > 0 {
            return min(seconds, 10.0)
        }
        return 1.0
    }

    private static func parseShortcutSpec(target: String, instruction: String) -> ShortcutSpec? {
        if target.hasPrefix("shortcut:") {
            let value = String(target.dropFirst("shortcut:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return ShortcutSpec(raw: value)
            }
        }

        if let normalized = normalizedShortcutExpression(from: instruction),
           let spec = ShortcutSpec(raw: normalized) {
            return spec
        }

        if instruction.contains("回车") || instruction.lowercased().contains("return") || instruction.lowercased().contains("enter") {
            return ShortcutSpec(raw: "return")
        }
        if instruction.lowercased().contains("tab") {
            return ShortcutSpec(raw: "tab")
        }
        if instruction.lowercased().contains("escape") || instruction.lowercased().contains("esc") {
            return ShortcutSpec(raw: "escape")
        }
        if instruction.contains("删除") || instruction.lowercased().contains("delete") || instruction.lowercased().contains("backspace") {
            return ShortcutSpec(raw: "delete")
        }
        return nil
    }

    private static func normalizedShortcutExpression(from instruction: String) -> String? {
        let patterns = [
            #"(?:快捷键|shortcut)\s*[:：]?\s*([A-Za-z0-9⌘⇧⌥⌃+\s＋]+)"#,
            #"([A-Za-z0-9⌘⇧⌥⌃]+(?:\s*[+＋]\s*[A-Za-z0-9⌘⇧⌥⌃]+)+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(
                      in: instruction,
                      options: [],
                      range: NSRange(location: 0, length: instruction.utf16.count)
                  ),
                  let range = Range(match.range(at: 1), in: instruction) else {
                continue
            }

            let raw = String(instruction[range])
            if let normalized = normalizeShortcutRawText(raw) {
                return normalized
            }
        }

        return nil
    }

    private static func normalizeShortcutRawText(_ raw: String) -> String? {
        let replaced = raw
            .replacingOccurrences(of: "＋", with: "+")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replaced.isEmpty else {
            return nil
        }

        let tokens = replaced.split(separator: "+").map { String($0) }
        let normalizedTokens = tokens.compactMap(normalizeShortcutToken)
        guard !normalizedTokens.isEmpty else {
            return nil
        }
        return normalizedTokens.joined(separator: "+")
    }

    private static func normalizeShortcutToken(_ token: String) -> String? {
        let raw = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "键", with: "")
        guard !raw.isEmpty else {
            return nil
        }

        switch raw {
        case "cmd", "command", "⌘":
            return "command"
        case "shift", "⇧":
            return "shift"
        case "option", "alt", "⌥":
            return "option"
        case "control", "ctrl", "⌃":
            return "control"
        case "return", "enter", "回车":
            return "return"
        case "tab":
            return "tab"
        case "esc", "escape":
            return "escape"
        case "delete", "backspace", "删除":
            return "delete"
        case "space", "空格":
            return "space"
        default:
            return raw
        }
    }

    private static func parseInputText(target: String, instruction: String) -> String? {
        if target.hasPrefix("text:") {
            let text = String(target.dropFirst("text:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }

        if let regex = try? NSRegularExpression(pattern: #"["“](.+?)["”]"#),
           let match = regex.firstMatch(
               in: instruction,
               options: [],
               range: NSRange(location: 0, length: instruction.utf16.count)
           ),
           let range = Range(match.range(at: 1), in: instruction) {
            return String(instruction[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let inputRange = instruction.range(of: "输入") {
            let tail = instruction[inputRange.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let separators = ["并回车", "并按回车", "并按下回车", "并确认", "后回车", "。", "，"]
            for separator in separators {
                if let sepRange = tail.range(of: separator) {
                    let prefix = tail[..<sepRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !prefix.isEmpty {
                        return prefix
                    }
                }
            }
            return tail.isEmpty ? nil : tail
        }
        return nil
    }

    private static func shouldPressReturnAfterInput(target: String, instruction: String) -> Bool {
        let lowerTarget = target.lowercased()
        if lowerTarget.hasPrefix("text+return:") || lowerTarget.hasPrefix("text-enter:") {
            return true
        }

        let lowerInstruction = instruction.lowercased()
        let enterHints = [
            "并回车",
            "并按回车",
            "并按下回车",
            "后回车",
            "并确认",
            "press enter",
            "press return"
        ]
        if enterHints.contains(where: { lowerInstruction.contains($0) }) {
            return true
        }

        // fallback for simplified phrasing such as "输入xxx回车"
        return lowerInstruction.contains("回车")
            || lowerInstruction.contains("enter")
            || lowerInstruction.contains("return")
    }

    private static func postShortcut(spec: ShortcutSpec) -> Bool {
        guard let keyCode = keyCode(for: spec.key),
              let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        let flags = modifierFlags(from: spec.modifiers)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.06)
        return true
    }

    private static func modifierFlags(from modifiers: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for modifier in modifiers {
            switch modifier {
            case "command", "cmd", "⌘":
                flags.insert(.maskCommand)
            case "shift", "⇧":
                flags.insert(.maskShift)
            case "option", "alt", "⌥":
                flags.insert(.maskAlternate)
            case "control", "ctrl", "⌃":
                flags.insert(.maskControl)
            default:
                continue
            }
        }
        return flags
    }

    private static func keyCode(for key: String) -> CGKeyCode? {
        let normalized = key.lowercased()
        switch normalized {
        case "a": return 0
        case "b": return 11
        case "c": return 8
        case "d": return 2
        case "e": return 14
        case "f": return 3
        case "g": return 5
        case "h": return 4
        case "i": return 34
        case "j": return 38
        case "k": return 40
        case "l": return 37
        case "m": return 46
        case "n": return 45
        case "o": return 31
        case "p": return 35
        case "q": return 12
        case "r": return 15
        case "s": return 1
        case "t": return 17
        case "u": return 32
        case "v": return 9
        case "w": return 13
        case "x": return 7
        case "y": return 16
        case "z": return 6
        case "0": return 29
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        case "8": return 28
        case "9": return 25
        case "space": return 49
        case "spacebar": return 49
        case "enter", "return": return 36
        case "tab": return 48
        case "esc", "escape": return 53
        case "delete", "backspace": return 51
        default: return nil
        }
    }
}

private struct ShortcutSpec {
    let raw: String
    let modifiers: [String]
    let key: String

    init?(raw: String) {
        let tokens = raw
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard let key = tokens.last else {
            return nil
        }
        self.raw = raw
        self.modifiers = Array(tokens.dropLast())
        self.key = key
    }
}
