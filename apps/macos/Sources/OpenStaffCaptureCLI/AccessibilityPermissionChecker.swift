import ApplicationServices
import Foundation

struct AccessibilityPermissionChecker {
    func isTrusted(prompt: Bool) -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [
            promptKey: prompt
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }
}
