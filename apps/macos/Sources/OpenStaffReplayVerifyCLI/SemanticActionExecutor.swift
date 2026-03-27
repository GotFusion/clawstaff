import AppKit
import ApplicationServices
import CryptoKit
import Foundation

enum SemanticActionExecutionStatus: String, Codable {
    case succeeded
    case blocked
    case failed
}

enum SemanticActionContextGuardStatus: String, Codable {
    case passed
    case blocked
    case skipped
}

struct SemanticActionContextGuardRequirements: Codable {
    let requiredFrontmostAppBundleId: String?
    let requiredFrontmostAppName: String?
    let windowTitlePattern: String?
    let urlHost: String?
}

struct SemanticActionContextGuardActualContext: Codable {
    let appName: String
    let appBundleId: String
    let windowTitle: String?
    let windowSignature: String?
    let url: String?
    let urlHost: String?
}

struct SemanticActionContextGuardMismatch: Codable {
    let dimension: String
    let expected: String
    let actual: String?
    let message: String
}

struct SemanticActionContextGuardResult: Codable {
    let status: SemanticActionContextGuardStatus
    let failurePolicy: String
    let requirements: SemanticActionContextGuardRequirements
    let actual: SemanticActionContextGuardActualContext
    let mismatches: [SemanticActionContextGuardMismatch]
}

struct SemanticActionExecutionReport: Codable {
    let schemaVersion: String
    let actionId: String
    let actionType: String
    let status: SemanticActionExecutionStatus
    let dryRun: Bool
    let summary: String
    let errorCode: String?
    let matchedLocatorType: String?
    let selectorHitPath: [String]
    let contextGuard: SemanticActionContextGuardResult?
    let durationMs: Int
    let executedAt: String
}

enum SemanticActionPerformStatus {
    case succeeded
    case blocked
    case failed
}

struct SemanticActionPerformOutcome {
    let status: SemanticActionPerformStatus
    let message: String
    let errorCode: String?
}

protocol SemanticActionPerforming {
    func activateApp(bundleId: String) -> Bool
    func focusWindow(appBundleId: String, windowTitlePattern: String?, windowSignature: String?) -> SemanticActionPerformOutcome
    func pressElement(_ snapshot: ReplayElementSnapshot, appBundleId: String) -> SemanticActionPerformOutcome
    func setText(_ snapshot: ReplayElementSnapshot, text: String, appBundleId: String) -> SemanticActionPerformOutcome
    func sendShortcut(keys: [String], appBundleId: String?) -> SemanticActionPerformOutcome
    func moveWindow(source: ReplayElementSnapshot, target: ReplayElementSnapshot, appBundleId: String) -> SemanticActionPerformOutcome
}

final class SemanticActionExecutor {
    private let snapshotProvider: any ReplayEnvironmentSnapshotProviding
    private let resolver: SemanticTargetResolver
    private let performer: any SemanticActionPerforming
    private let nowProvider: () -> Date
    private let formatter: ISO8601DateFormatter

    init(
        snapshotProvider: any ReplayEnvironmentSnapshotProviding = LiveReplayEnvironmentSnapshotProvider(),
        resolver: SemanticTargetResolver = SemanticTargetResolver(),
        performer: any SemanticActionPerforming = LiveSemanticActionPerformer(),
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.snapshotProvider = snapshotProvider
        self.resolver = resolver
        self.performer = performer
        self.nowProvider = nowProvider

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter
    }

    func execute(
        action: SemanticActionStoreAction,
        dryRun: Bool
    ) -> SemanticActionExecutionReport {
        let started = nowProvider()
        let contextSnapshot = snapshotProvider.snapshot()
        let contextGuard = evaluateContextGuard(action: action, snapshot: contextSnapshot)
        if contextGuard.status == .blocked {
            let mismatchSummary = contextGuard.mismatches
                .map(\.message)
                .joined(separator: "；")
            return finalize(
                action: action,
                dryRun: dryRun,
                started: started,
                status: .blocked,
                summary: "Context guard blocked execution. policy=\(contextGuard.failurePolicy). \(mismatchSummary)",
                errorCode: "SEM202-CONTEXT-MISMATCH",
                matchedLocatorType: nil,
                selectorHitPath: [],
                contextGuard: contextGuard
            )
        }

        let outcome: SemanticActionExecutionReport
        switch action.actionType {
        case "switch_app":
            outcome = executeSwitchApp(action: action, dryRun: dryRun, started: started)
        case "focus_window":
            outcome = executeFocusWindow(action: action, dryRun: dryRun, started: started)
        case "shortcut":
            outcome = executeShortcut(action: action, dryRun: dryRun, started: started)
        case "click":
            outcome = executeElementAction(action: action, dryRun: dryRun, started: started, kind: .click)
        case "type":
            outcome = executeElementAction(action: action, dryRun: dryRun, started: started, kind: .type)
        case "drag":
            outcome = executeDrag(action: action, dryRun: dryRun, started: started)
        default:
            outcome = finalize(
                action: action,
                dryRun: dryRun,
                started: started,
                status: .failed,
                summary: "Unsupported semantic action type: \(action.actionType)",
                errorCode: "SEM201-UNSUPPORTED-ACTION",
                matchedLocatorType: nil,
                selectorHitPath: []
            )
        }

        return outcome
    }

    private enum ElementActionKind {
        case click
        case type
    }

    private func executeSwitchApp(
        action: SemanticActionStoreAction,
        dryRun: Bool,
        started: Date
    ) -> SemanticActionExecutionReport {
        guard let bundleId = string(action.args["toAppBundleId"]) ?? string(action.selector["appBundleId"]),
              !bundleId.isEmpty else {
            return finalize(
                action: action,
                dryRun: dryRun,
                started: started,
                status: .failed,
                summary: "switch_app 缺少目标 appBundleId。",
                errorCode: "SEM201-MISSING-APP-BUNDLE",
                matchedLocatorType: "app_context",
                selectorHitPath: ["app_context"]
            )
        }

        if dryRun {
            return finalize(
                action: action,
                dryRun: true,
                started: started,
                status: .succeeded,
                summary: "Dry-run: would activate app \(bundleId).",
                errorCode: nil,
                matchedLocatorType: "app_context",
                selectorHitPath: ["app_context"]
            )
        }

        let activated = performer.activateApp(bundleId: bundleId)
        return finalize(
            action: action,
            dryRun: false,
            started: started,
            status: activated ? .succeeded : .failed,
            summary: activated ? "Activated app \(bundleId)." : "Failed to activate app \(bundleId).",
            errorCode: activated ? nil : "SEM201-APP-ACTIVATION-FAILED",
            matchedLocatorType: "app_context",
            selectorHitPath: ["app_context"]
        )
    }

    private func executeFocusWindow(
        action: SemanticActionStoreAction,
        dryRun: Bool,
        started: Date
    ) -> SemanticActionExecutionReport {
        guard let bundleId = string(action.selector["appBundleId"]),
              !bundleId.isEmpty else {
            return finalize(
                action: action,
                dryRun: dryRun,
                started: started,
                status: .failed,
                summary: "focus_window 缺少上下文 appBundleId。",
                errorCode: "SEM201-MISSING-APP-BUNDLE",
                matchedLocatorType: "window_context",
                selectorHitPath: ["window_context"]
            )
        }

        let pattern = string(action.selector["windowTitlePattern"])
        let signature = windowSignatureValue(action.selector["windowSignature"])

        if dryRun {
            let snapshot = snapshotProvider.snapshot()
            let windowMatches = snapshot.appBundleId == bundleId
                && matchesWindow(snapshot: snapshot, windowTitlePattern: pattern, windowSignature: signature)
            return finalize(
                action: action,
                dryRun: true,
                started: started,
                status: windowMatches ? .succeeded : .failed,
                summary: windowMatches
                    ? "Dry-run: focus_window context matches current snapshot."
                    : "Dry-run: current snapshot does not match focus_window selector.",
                errorCode: windowMatches ? nil : "SEM201-WINDOW-UNRESOLVED",
                matchedLocatorType: "window_context",
                selectorHitPath: ["window_context"]
            )
        }

        guard performer.activateApp(bundleId: bundleId) else {
            return finalize(
                action: action,
                dryRun: false,
                started: started,
                status: .failed,
                summary: "Failed to activate app \(bundleId) before focus_window.",
                errorCode: "SEM201-APP-ACTIVATION-FAILED",
                matchedLocatorType: "window_context",
                selectorHitPath: ["window_context"]
            )
        }

        let performOutcome = performer.focusWindow(
            appBundleId: bundleId,
            windowTitlePattern: pattern,
            windowSignature: signature
        )
        return finalize(
            action: action,
            dryRun: false,
            started: started,
            status: mapStatus(performOutcome.status),
            summary: performOutcome.message,
            errorCode: performOutcome.errorCode,
            matchedLocatorType: "window_context",
            selectorHitPath: ["window_context"]
        )
    }

    private func executeShortcut(
        action: SemanticActionStoreAction,
        dryRun: Bool,
        started: Date
    ) -> SemanticActionExecutionReport {
        let keys = shortcutKeys(from: action.args)
        guard !keys.isEmpty else {
            return finalize(
                action: action,
                dryRun: dryRun,
                started: started,
                status: .failed,
                summary: "shortcut 缺少 keys。",
                errorCode: "SEM201-MISSING-SHORTCUT-KEYS",
                matchedLocatorType: nil,
                selectorHitPath: []
            )
        }

        let bundleId = string(action.selector["appBundleId"])
        if dryRun {
            let joinedKeys = keys.joined(separator: "+")
            return finalize(
                action: action,
                dryRun: true,
                started: started,
                status: .succeeded,
                summary: "Dry-run: would send shortcut \(joinedKeys).",
                errorCode: nil,
                matchedLocatorType: bundleId == nil ? nil : "app_context",
                selectorHitPath: bundleId == nil ? [] : ["app_context"]
            )
        }

        let performOutcome = performer.sendShortcut(keys: keys, appBundleId: bundleId)
        return finalize(
            action: action,
            dryRun: false,
            started: started,
            status: mapStatus(performOutcome.status),
            summary: performOutcome.message,
            errorCode: performOutcome.errorCode,
            matchedLocatorType: bundleId == nil ? nil : "app_context",
            selectorHitPath: bundleId == nil ? [] : ["app_context"]
        )
    }

    private func executeElementAction(
        action: SemanticActionStoreAction,
        dryRun: Bool,
        started: Date,
        kind: ElementActionKind
    ) -> SemanticActionExecutionReport {
        let candidates = semanticTargets(
            for: action,
            targetRolePrefixes: ["primary", "candidate", "fallback"],
            fallbackSelector: action.selector
        )
        if candidates.isEmpty {
            return finalize(
                action: action,
                dryRun: dryRun,
                started: started,
                status: .blocked,
                summary: "Action lacks non-coordinate semantic selector candidates.",
                errorCode: "SEM201-SEMANTIC-TARGET-REQUIRED",
                matchedLocatorType: nil,
                selectorHitPath: []
            )
        }

        let appBundleId = candidates.first?.appBundleId ?? string(action.selector["appBundleId"]) ?? ""
        if !dryRun, !appBundleId.isEmpty, !performer.activateApp(bundleId: appBundleId) {
            return finalize(
                action: action,
                dryRun: false,
                started: started,
                status: .failed,
                summary: "Failed to activate app \(appBundleId) before \(action.actionType).",
                errorCode: "SEM201-APP-ACTIVATION-FAILED",
                matchedLocatorType: nil,
                selectorHitPath: []
            )
        }

        let snapshot = snapshotProvider.snapshot()
        let resolution = resolver.resolve(
            targets: candidates,
            preferredLocatorType: preferredLocatorType(
                rawValue: action.preferredLocatorType
            ),
            coordinate: nil,
            in: snapshot
        )
        let selectorHitPath = selectorHitPath(from: resolution)

        if resolution.matchedLocatorType == .coordinateFallback {
            return finalize(
                action: action,
                dryRun: dryRun,
                started: started,
                status: .blocked,
                summary: "Coordinate fallback is disabled for semantic execution.",
                errorCode: "SEM201-COORDINATE-FALLBACK-DISALLOWED",
                matchedLocatorType: resolution.matchedLocatorType?.rawValue,
                selectorHitPath: selectorHitPath
            )
        }

        guard resolution.status == .resolved,
              let matchedElement = resolution.matchedElement else {
            return finalize(
                action: action,
                dryRun: dryRun,
                started: started,
                status: .failed,
                summary: resolution.message,
                errorCode: "SEM201-TARGET-UNRESOLVED",
                matchedLocatorType: resolution.matchedLocatorType?.rawValue,
                selectorHitPath: selectorHitPath
            )
        }

        if dryRun {
            let resolvedLocator = resolution.matchedLocatorType?.rawValue ?? "unknown"
            return finalize(
                action: action,
                dryRun: true,
                started: started,
                status: .succeeded,
                summary: "Dry-run: resolved \(action.actionType) target via \(resolvedLocator).",
                errorCode: nil,
                matchedLocatorType: resolution.matchedLocatorType?.rawValue,
                selectorHitPath: selectorHitPath
            )
        }

        let performOutcome: SemanticActionPerformOutcome
        switch kind {
        case .click:
            performOutcome = performer.pressElement(matchedElement, appBundleId: appBundleId)
        case .type:
            guard let text = string(action.args["text"]), !text.isEmpty else {
                return finalize(
                    action: action,
                    dryRun: false,
                    started: started,
                    status: .failed,
                    summary: "type action 缺少 text。",
                    errorCode: "SEM201-MISSING-TYPE-TEXT",
                    matchedLocatorType: resolution.matchedLocatorType?.rawValue,
                    selectorHitPath: selectorHitPath
                )
            }
            performOutcome = performer.setText(matchedElement, text: text, appBundleId: appBundleId)
        }

        return finalize(
            action: action,
            dryRun: false,
            started: started,
            status: mapStatus(performOutcome.status),
            summary: performOutcome.message,
            errorCode: performOutcome.errorCode,
            matchedLocatorType: resolution.matchedLocatorType?.rawValue,
            selectorHitPath: selectorHitPath
        )
    }

    private func executeDrag(
        action: SemanticActionStoreAction,
        dryRun: Bool,
        started: Date
    ) -> SemanticActionExecutionReport {
        let sourceTargets = semanticTargets(for: action, targetRolePrefixes: ["source"], fallbackSelector: selector(action.args["sourceSelector"]))
        let targetTargets = semanticTargets(for: action, targetRolePrefixes: ["target"], fallbackSelector: selector(action.args["targetSelector"]))
        if sourceTargets.isEmpty || targetTargets.isEmpty {
            return finalize(
                action: action,
                dryRun: dryRun,
                started: started,
                status: .blocked,
                summary: "drag 缺少 source/target 语义选择器。",
                errorCode: "SEM201-SEMANTIC-TARGET-REQUIRED",
                matchedLocatorType: nil,
                selectorHitPath: []
            )
        }

        let appBundleId = sourceTargets.first?.appBundleId ?? targetTargets.first?.appBundleId ?? ""
        if !dryRun, !appBundleId.isEmpty, !performer.activateApp(bundleId: appBundleId) {
            return finalize(
                action: action,
                dryRun: false,
                started: started,
                status: .failed,
                summary: "Failed to activate app \(appBundleId) before drag.",
                errorCode: "SEM201-APP-ACTIVATION-FAILED",
                matchedLocatorType: nil,
                selectorHitPath: []
            )
        }

        let snapshot = snapshotProvider.snapshot()
        let sourceResolution = resolver.resolve(
            targets: sourceTargets,
            preferredLocatorType: preferredLocatorType(rawValue: action.preferredLocatorType),
            coordinate: nil,
            in: snapshot
        )
        let targetResolution = resolver.resolve(
            targets: targetTargets,
            preferredLocatorType: preferredLocatorType(rawValue: action.preferredLocatorType),
            coordinate: nil,
            in: snapshot
        )

        let sourceHitPath = selectorHitPath(from: sourceResolution).map { "source:\($0)" }
        let targetHitPath = selectorHitPath(from: targetResolution).map { "target:\($0)" }
        let selectorHitPath = sourceHitPath + targetHitPath

        if sourceResolution.matchedLocatorType == .coordinateFallback || targetResolution.matchedLocatorType == .coordinateFallback {
            return finalize(
                action: action,
                dryRun: dryRun,
                started: started,
                status: .blocked,
                summary: "Coordinate fallback is disabled for semantic drag execution.",
                errorCode: "SEM201-COORDINATE-FALLBACK-DISALLOWED",
                matchedLocatorType: sourceResolution.matchedLocatorType?.rawValue,
                selectorHitPath: selectorHitPath
            )
        }

        guard sourceResolution.status == .resolved,
              let sourceMatched = sourceResolution.matchedElement,
              targetResolution.status == .resolved,
              let targetMatched = targetResolution.matchedElement else {
            return finalize(
                action: action,
                dryRun: dryRun,
                started: started,
                status: .failed,
                summary: sourceResolution.status == .resolved ? targetResolution.message : sourceResolution.message,
                errorCode: "SEM201-TARGET-UNRESOLVED",
                matchedLocatorType: sourceResolution.matchedLocatorType?.rawValue,
                selectorHitPath: selectorHitPath
            )
        }

        let intent = string(action.args["intent"]) ?? "drag_and_drop"
        if dryRun {
            return finalize(
                action: action,
                dryRun: true,
                started: started,
                status: .succeeded,
                summary: "Dry-run: would execute drag intent=\(intent).",
                errorCode: nil,
                matchedLocatorType: sourceResolution.matchedLocatorType?.rawValue,
                selectorHitPath: selectorHitPath
            )
        }

        guard intent == "window_move" else {
            return finalize(
                action: action,
                dryRun: false,
                started: started,
                status: .blocked,
                summary: "Live drag currently supports only window_move intent.",
                errorCode: "SEM201-UNSUPPORTED-DRAG-INTENT",
                matchedLocatorType: sourceResolution.matchedLocatorType?.rawValue,
                selectorHitPath: selectorHitPath
            )
        }

        let performOutcome = performer.moveWindow(source: sourceMatched, target: targetMatched, appBundleId: appBundleId)
        return finalize(
            action: action,
            dryRun: false,
            started: started,
            status: mapStatus(performOutcome.status),
            summary: performOutcome.message,
            errorCode: performOutcome.errorCode,
            matchedLocatorType: sourceResolution.matchedLocatorType?.rawValue,
            selectorHitPath: selectorHitPath
        )
    }

    private func semanticTargets(
        for action: SemanticActionStoreAction,
        targetRolePrefixes: [String],
        fallbackSelector: SemanticJSONObject?
    ) -> [SemanticTarget] {
        let orderedTargets = action.targets
            .filter { target in
                let role = target.targetRole.lowercased()
                return targetRolePrefixes.contains(where: { role.hasPrefix($0.lowercased()) })
            }
            .sorted { lhs, rhs in
                if lhs.ordinal == rhs.ordinal {
                    return lhs.targetId < rhs.targetId
                }
                return lhs.ordinal < rhs.ordinal
            }

        let parsedTargets = orderedTargets.compactMap { semanticTarget(from: $0.selector) }
        if !parsedTargets.isEmpty {
            return parsedTargets
        }

        if let fallbackSelector,
           let target = semanticTarget(from: fallbackSelector) {
            return [target]
        }

        if let primary = semanticTarget(from: action.selector) {
            return [primary]
        }

        return []
    }

    private func semanticTarget(from payload: SemanticJSONObject) -> SemanticTarget? {
        guard let rawLocatorType = string(payload["locatorType"]),
              let locatorType = SemanticLocatorType(rawValue: rawLocatorType),
              locatorType != .coordinateFallback else {
            return nil
        }
        guard let appBundleId = string(payload["appBundleId"]), !appBundleId.isEmpty else {
            return nil
        }

        return SemanticTarget(
            locatorType: locatorType,
            appBundleId: appBundleId,
            windowTitlePattern: string(payload["windowTitlePattern"]),
            windowSignature: windowSignatureValue(payload["windowSignature"]),
            elementRole: string(payload["elementRole"]),
            elementTitle: string(payload["elementTitle"]),
            elementIdentifier: string(payload["elementIdentifier"]),
            axPath: string(payload["axPath"]) ?? string(payload["ancestryPath"]),
            textAnchor: string(payload["textAnchor"]),
            imageAnchor: imageAnchor(payload["imageAnchor"]),
            boundingRect: boundingRect(payload["boundingRect"]),
            confidence: double(payload["confidence"]) ?? 0.0,
            source: .capture
        )
    }

    private func preferredLocatorType(rawValue: String?) -> SemanticLocatorType? {
        guard let rawValue else {
            return nil
        }
        return SemanticLocatorType(rawValue: rawValue)
    }

    private func selectorHitPath(from resolution: SemanticTargetResolution) -> [String] {
        resolution.attempts.map { $0.locatorType.rawValue }
    }

    private func evaluateContextGuard(
        action: SemanticActionStoreAction,
        snapshot: ReplayEnvironmentSnapshot
    ) -> SemanticActionContextGuardResult {
        let requirements = contextGuardRequirements(for: action)
        let failurePolicy = contextGuardFailurePolicy(for: action)
        let actual = SemanticActionContextGuardActualContext(
            appName: snapshot.appName,
            appBundleId: snapshot.appBundleId,
            windowTitle: snapshot.windowTitle,
            windowSignature: snapshot.windowSignature?.signature,
            url: snapshot.url,
            urlHost: normalizedURLHost(snapshot.urlHost) ?? normalizedURLHost(snapshot.url)
        )

        let enforcedDimensions = [
            requirements.requiredFrontmostAppBundleId,
            requirements.windowTitlePattern,
            requirements.urlHost,
        ]
        .compactMap { $0 }

        guard !enforcedDimensions.isEmpty else {
            return SemanticActionContextGuardResult(
                status: .skipped,
                failurePolicy: failurePolicy,
                requirements: requirements,
                actual: actual,
                mismatches: []
            )
        }

        var mismatches: [SemanticActionContextGuardMismatch] = []

        if let requiredFrontmostAppBundleId = requirements.requiredFrontmostAppBundleId,
           normalizedText(requiredFrontmostAppBundleId) != normalizedText(actual.appBundleId) {
            let expected = formattedExpectedApp(
                bundleId: requiredFrontmostAppBundleId,
                appName: requirements.requiredFrontmostAppName
            )
            let actualValue = formattedExpectedApp(bundleId: actual.appBundleId, appName: actual.appName)
            mismatches.append(
                SemanticActionContextGuardMismatch(
                    dimension: "requiredFrontmostApp",
                    expected: expected,
                    actual: actualValue,
                    message: "requiredFrontmostApp mismatch. expected=\(expected) actual=\(actualValue)"
                )
            )
            return SemanticActionContextGuardResult(
                status: .blocked,
                failurePolicy: failurePolicy,
                requirements: requirements,
                actual: actual,
                mismatches: mismatches
            )
        }

        if let windowTitlePattern = requirements.windowTitlePattern,
           !matchesRegex(windowTitlePattern, actual.windowTitle) {
            mismatches.append(
                SemanticActionContextGuardMismatch(
                    dimension: "windowTitlePattern",
                    expected: windowTitlePattern,
                    actual: actual.windowTitle,
                    message: "windowTitlePattern mismatch. expected=\(windowTitlePattern) actual=\(actual.windowTitle ?? "<nil>")"
                )
            )
        }

        if let urlHost = requirements.urlHost,
           normalizedText(urlHost) != normalizedText(actual.urlHost) {
            mismatches.append(
                SemanticActionContextGuardMismatch(
                    dimension: "urlHost",
                    expected: urlHost,
                    actual: actual.urlHost,
                    message: "urlHost mismatch. expected=\(urlHost) actual=\(actual.urlHost ?? "<nil>")"
                )
            )
        }

        return SemanticActionContextGuardResult(
            status: mismatches.isEmpty ? .passed : .blocked,
            failurePolicy: failurePolicy,
            requirements: requirements,
            actual: actual,
            mismatches: mismatches
        )
    }

    private func contextGuardRequirements(for action: SemanticActionStoreAction) -> SemanticActionContextGuardRequirements {
        let config = selector(action.context["contextGuard"]) ?? [:]
        let disabledDimensions = Set(
            stringArray(config["disabledDimensions"])
                .map { normalizedText($0) ?? "" }
        )
        let appContext = selector(action.context["appContext"]) ?? [:]

        func allows(_ dimension: String) -> Bool {
            !disabledDimensions.contains(normalizedText(dimension) ?? "")
        }

        let requiredFrontmostAppBundleId: String?
        let requiredFrontmostAppName: String?
        let windowTitlePattern: String?
        let urlHost: String?

        switch action.actionType {
        case "switch_app":
            requiredFrontmostAppBundleId = allows("requiredFrontmostApp")
                ? string(config["requiredFrontmostAppBundleId"]) ?? string(action.args["fromAppBundleId"])
                : nil
            requiredFrontmostAppName = string(config["requiredFrontmostAppName"]) ?? string(action.args["fromAppName"])
            windowTitlePattern = allows("windowTitlePattern")
                ? string(config["windowTitlePattern"])
                : nil
            urlHost = allows("urlHost")
                ? normalizedURLHost(config["urlHost"]) ?? normalizedURLHost(config["url"])
                : nil
        case "focus_window":
            requiredFrontmostAppBundleId = allows("requiredFrontmostApp")
                ? string(config["requiredFrontmostAppBundleId"])
                    ?? string(action.selector["appBundleId"])
                    ?? assertionValue(action.assertions, type: "requiredFrontmostApp", key: "appBundleId")
                    ?? string(appContext["appBundleId"])
                : nil
            requiredFrontmostAppName = string(config["requiredFrontmostAppName"]) ?? string(action.selector["appName"]) ?? string(appContext["appName"])
            windowTitlePattern = allows("windowTitlePattern")
                ? string(config["windowTitlePattern"])
                    ?? exactWindowTitlePattern(for: string(action.args["fromWindowTitle"]))
                    ?? string(action.args["fromWindowPattern"])
                    ?? assertionValue(action.assertions, type: "windowTitlePattern", key: "pattern")
                : nil
            urlHost = allows("urlHost")
                ? normalizedURLHost(config["urlHost"])
                    ?? normalizedURLHost(config["url"])
                : nil
        default:
            requiredFrontmostAppBundleId = allows("requiredFrontmostApp")
                ? string(config["requiredFrontmostAppBundleId"])
                    ?? assertionValue(action.assertions, type: "requiredFrontmostApp", key: "appBundleId")
                    ?? string(action.selector["appBundleId"])
                    ?? string(appContext["appBundleId"])
                : nil
            requiredFrontmostAppName = string(config["requiredFrontmostAppName"]) ?? string(action.selector["appName"]) ?? string(appContext["appName"])
            windowTitlePattern = allows("windowTitlePattern")
                ? string(config["windowTitlePattern"])
                    ?? assertionValue(action.assertions, type: "windowTitlePattern", key: "pattern")
                    ?? string(action.selector["windowTitlePattern"])
                    ?? exactWindowTitlePattern(for: string(appContext["windowTitle"]))
                : nil
            urlHost = allows("urlHost")
                ? normalizedURLHost(config["urlHost"])
                    ?? normalizedURLHost(config["url"])
                    ?? normalizedURLHost(action.selector["urlHost"])
                    ?? normalizedURLHost(action.selector["url"])
                    ?? normalizedURLHost(appContext["urlHost"])
                    ?? normalizedURLHost(appContext["url"])
                : nil
        }

        return SemanticActionContextGuardRequirements(
            requiredFrontmostAppBundleId: requiredFrontmostAppBundleId,
            requiredFrontmostAppName: requiredFrontmostAppName,
            windowTitlePattern: windowTitlePattern,
            urlHost: urlHost
        )
    }

    private func contextGuardFailurePolicy(for action: SemanticActionStoreAction) -> String {
        let config = selector(action.context["contextGuard"]) ?? [:]
        return string(config["onMismatch"]) ?? "stopAndAskTeacher"
    }

    private func assertionValue(
        _ assertions: [SemanticActionStoreAssertionRecord],
        type: String,
        key: String
    ) -> String? {
        guard let payload = assertions.first(where: { $0.assertionType == type })?.payload else {
            return nil
        }
        return string(payload[key])
    }

    private func stringArray(_ value: Any?) -> [String] {
        guard let raw = value as? [Any] else {
            return []
        }
        return raw.compactMap(string)
    }

    private func exactWindowTitlePattern(for title: String?) -> String? {
        guard let title = string(title) else {
            return nil
        }
        return "^\(NSRegularExpression.escapedPattern(for: title))$"
    }

    private func matchesRegex(_ pattern: String, _ value: String?) -> Bool {
        guard let value = string(value),
              let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }

    private func normalizedURLHost(_ value: Any?) -> String? {
        if let host = string(value) {
            if let parsedHost = URL(string: host)?.host,
               let normalizedParsedHost = normalizedText(parsedHost) {
                return normalizedParsedHost
            }
            return normalizedText(host)
        }
        return nil
    }

    private func formattedExpectedApp(bundleId: String?, appName: String?) -> String {
        let trimmedBundle = string(bundleId)
        let trimmedName = string(appName)
        switch (trimmedName, trimmedBundle) {
        case let (name?, bundle?):
            return "\(name) (\(bundle))"
        case let (name?, nil):
            return name
        case let (nil, bundle?):
            return bundle
        case (nil, nil):
            return "<nil>"
        }
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }

    private func finalize(
        action: SemanticActionStoreAction,
        dryRun: Bool,
        started: Date,
        status: SemanticActionExecutionStatus,
        summary: String,
        errorCode: String?,
        matchedLocatorType: String?,
        selectorHitPath: [String],
        contextGuard: SemanticActionContextGuardResult? = nil
    ) -> SemanticActionExecutionReport {
        let finished = nowProvider()
        return SemanticActionExecutionReport(
            schemaVersion: "openstaff.semantic-action-execution.v0",
            actionId: action.actionId,
            actionType: action.actionType,
            status: status,
            dryRun: dryRun,
            summary: summary,
            errorCode: errorCode,
            matchedLocatorType: matchedLocatorType,
            selectorHitPath: selectorHitPath,
            contextGuard: contextGuard,
            durationMs: max(Int(finished.timeIntervalSince(started) * 1000), 0),
            executedAt: formatter.string(from: finished)
        )
    }

    private func mapStatus(_ status: SemanticActionPerformStatus) -> SemanticActionExecutionStatus {
        switch status {
        case .succeeded:
            return .succeeded
        case .blocked:
            return .blocked
        case .failed:
            return .failed
        }
    }

    private func shortcutKeys(from payload: SemanticJSONObject) -> [String] {
        if let keys = payload["keys"] as? [String] {
            return keys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        }

        if let single = string(payload["keys"]) {
            return [single.lowercased()]
        }

        return []
    }

    private func matchesWindow(
        snapshot: ReplayEnvironmentSnapshot,
        windowTitlePattern: String?,
        windowSignature: String?
    ) -> Bool {
        if let windowSignature,
           snapshot.windowSignature?.signature != windowSignature {
            return false
        }

        guard let windowTitlePattern else {
            return true
        }
        guard let windowTitle = snapshot.windowTitle else {
            return false
        }
        return windowTitle.range(of: windowTitlePattern, options: .regularExpression) != nil
    }

    private func selector(_ value: Any?) -> SemanticJSONObject? {
        value as? SemanticJSONObject
    }

    private func string(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let text = value as? String {
            return Double(text)
        }
        return nil
    }

    private func windowSignatureValue(_ value: Any?) -> String? {
        if let string = string(value) {
            return string
        }
        if let payload = value as? SemanticJSONObject {
            return string(payload["signature"])
        }
        return nil
    }

    private func imageAnchor(_ value: Any?) -> SemanticImageAnchor? {
        guard let payload = value as? SemanticJSONObject,
              let pixelHash = string(payload["pixelHash"]),
              let averageLuma = double(payload["averageLuma"]) else {
            return nil
        }
        return SemanticImageAnchor(
            pixelHash: pixelHash,
            averageLuma: averageLuma,
            sampleWidth: integer(payload["sampleWidth"]),
            sampleHeight: integer(payload["sampleHeight"])
        )
    }

    private func boundingRect(_ value: Any?) -> SemanticBoundingRect? {
        guard let payload = value as? SemanticJSONObject,
              let x = double(payload["x"]),
              let y = double(payload["y"]),
              let width = double(payload["width"]),
              let height = double(payload["height"]) else {
            return nil
        }
        return SemanticBoundingRect(x: x, y: y, width: width, height: height)
    }

    private func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let text = value as? String {
            return Int(text)
        }
        return nil
    }
}

private final class LiveSemanticActionPerformer: SemanticActionPerforming {
    func activateApp(bundleId: String) -> Bool {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier == bundleId {
            return true
        }

        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            let activated = running.activate(options: [.activateAllWindows])
            if activated {
                Thread.sleep(forTimeInterval: 0.20)
                return true
            }
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        let semaphore = DispatchSemaphore(value: 0)
        var opened = false
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

    func focusWindow(
        appBundleId: String,
        windowTitlePattern: String?,
        windowSignature: String?
    ) -> SemanticActionPerformOutcome {
        guard let window = locateWindow(appBundleId: appBundleId, windowTitlePattern: windowTitlePattern, windowSignature: windowSignature) else {
            return SemanticActionPerformOutcome(
                status: .failed,
                message: "Failed to locate target window.",
                errorCode: "SEM201-WINDOW-UNRESOLVED"
            )
        }

        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return SemanticActionPerformOutcome(status: .succeeded, message: "Focused matching window.", errorCode: nil)
    }

    func pressElement(_ snapshot: ReplayElementSnapshot, appBundleId: String) -> SemanticActionPerformOutcome {
        guard let element = resolveElement(snapshot: snapshot, appBundleId: appBundleId) else {
            return SemanticActionPerformOutcome(
                status: .failed,
                message: "Failed to resolve AX element for click.",
                errorCode: "SEM201-TARGET-UNRESOLVED"
            )
        }

        if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            return SemanticActionPerformOutcome(status: .succeeded, message: "Pressed target element.", errorCode: nil)
        }
        if AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success {
            return SemanticActionPerformOutcome(status: .succeeded, message: "Raised target element.", errorCode: nil)
        }

        return SemanticActionPerformOutcome(
            status: .failed,
            message: "Target element does not support AXPress/AXRaise.",
            errorCode: "SEM201-PRESS-FAILED"
        )
    }

    func setText(_ snapshot: ReplayElementSnapshot, text: String, appBundleId: String) -> SemanticActionPerformOutcome {
        guard let element = resolveElement(snapshot: snapshot, appBundleId: appBundleId) else {
            return SemanticActionPerformOutcome(
                status: .failed,
                message: "Failed to resolve AX element for type.",
                errorCode: "SEM201-TARGET-UNRESOLVED"
            )
        }

        _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        if AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString) == .success {
            return SemanticActionPerformOutcome(status: .succeeded, message: "Updated element value via AXValue.", errorCode: nil)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success,
           sendShortcut(keys: ["command", "v"], appBundleId: appBundleId).status == .succeeded {
            return SemanticActionPerformOutcome(status: .succeeded, message: "Filled element text via paste fallback.", errorCode: nil)
        }

        return SemanticActionPerformOutcome(
            status: .failed,
            message: "Failed to write text to target element.",
            errorCode: "SEM201-TYPE-FAILED"
        )
    }

    func sendShortcut(keys: [String], appBundleId: String?) -> SemanticActionPerformOutcome {
        if let appBundleId, !appBundleId.isEmpty, !activateApp(bundleId: appBundleId) {
            return SemanticActionPerformOutcome(
                status: .failed,
                message: "Failed to activate app \(appBundleId) before shortcut.",
                errorCode: "SEM201-APP-ACTIVATION-FAILED"
            )
        }

        guard let spec = ShortcutSpec(keys: keys),
              let keyCode = keyCode(for: spec.key),
              let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return SemanticActionPerformOutcome(
                status: .failed,
                message: "Failed to synthesize keyboard shortcut.",
                errorCode: "SEM201-SHORTCUT-FAILED"
            )
        }

        let flags = modifierFlags(from: spec.modifiers)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        return SemanticActionPerformOutcome(status: .succeeded, message: "Sent shortcut \(spec.raw).", errorCode: nil)
    }

    func moveWindow(source: ReplayElementSnapshot, target: ReplayElementSnapshot, appBundleId: String) -> SemanticActionPerformOutcome {
        guard let window = resolveWindowForSnapshot(source, appBundleId: appBundleId) ?? locateFocusedWindow(appBundleId: appBundleId),
              let targetRect = target.boundingRect else {
            return SemanticActionPerformOutcome(
                status: .failed,
                message: "Failed to resolve window or target rect for drag.",
                errorCode: "SEM201-DRAG-FAILED"
            )
        }

        var point = CGPoint(x: targetRect.x, y: targetRect.y)
        guard let axValue = AXValueCreate(.cgPoint, &point),
              AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue) == .success else {
            return SemanticActionPerformOutcome(
                status: .failed,
                message: "Failed to move window via AXPosition.",
                errorCode: "SEM201-DRAG-FAILED"
            )
        }

        return SemanticActionPerformOutcome(status: .succeeded, message: "Moved window to target position.", errorCode: nil)
    }

    private func resolveWindowForSnapshot(_ snapshot: ReplayElementSnapshot, appBundleId: String) -> AXUIElement? {
        if snapshot.role == "AXWindow" || snapshot.subrole == "AXWindow" {
            return resolveElement(snapshot: snapshot, appBundleId: appBundleId)
        }
        return locateFocusedWindow(appBundleId: appBundleId)
    }

    private func resolveElement(snapshot: ReplayElementSnapshot, appBundleId: String) -> AXUIElement? {
        guard let window = locateFocusedWindow(appBundleId: appBundleId) else {
            return nil
        }

        if let axPath = snapshot.axPath,
           let matched = element(for: axPath, from: window) {
            return matched
        }

        let candidates = enumerateElements(from: window, path: "AXWindow", depth: 0)
        let bestMatch = candidates
            .map { (element: $0.element, snapshot: $0.snapshot, score: score(snapshot: snapshot, candidate: $0.snapshot)) }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return (lhs.snapshot.axPath ?? "") < (rhs.snapshot.axPath ?? "")
                }
                return lhs.score > rhs.score
            }
            .first

        return bestMatch?.element
    }

    private func locateFocusedWindow(appBundleId: String) -> AXUIElement? {
        guard let application = runningApplication(bundleId: appBundleId) else {
            return nil
        }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        return axElementAttribute(kAXFocusedWindowAttribute as CFString, from: appElement)
            ?? axElementAttribute(kAXMainWindowAttribute as CFString, from: appElement)
    }

    private func locateWindow(
        appBundleId: String,
        windowTitlePattern: String?,
        windowSignature: String?
    ) -> AXUIElement? {
        guard let application = runningApplication(bundleId: appBundleId) else {
            return nil
        }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let windows = axElementArrayAttribute(kAXWindowsAttribute as CFString, from: appElement)
        return windows.first { window in
            let title = stringAttribute(kAXTitleAttribute as CFString, from: window)
            if let windowTitlePattern {
                guard let title,
                      title.range(of: windowTitlePattern, options: .regularExpression) != nil else {
                    return false
                }
            }

            if let windowSignature {
                return buildWindowSignature(windowElement: window, appBundleId: appBundleId, windowTitle: title)?.signature == windowSignature
            }

            return true
        }
    }

    private func runningApplication(bundleId: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }

    private func element(for axPath: String, from root: AXUIElement) -> AXUIElement? {
        let segments = axPath
            .split(separator: "/")
            .map(String.init)
        guard !segments.isEmpty else {
            return nil
        }

        var current = root
        for segment in segments.dropFirst() {
            guard let indexStart = segment.lastIndex(of: "["),
                  let indexEnd = segment.lastIndex(of: "]"),
                  indexEnd > indexStart else {
                return nil
            }
            let indexText = segment[segment.index(after: indexStart)..<indexEnd]
            guard let index = Int(indexText) else {
                return nil
            }
            let children = childElements(from: current)
            guard index >= 0, index < children.count else {
                return nil
            }
            current = children[index]
        }

        return current
    }

    private func enumerateElements(
        from element: AXUIElement,
        path: String,
        depth: Int,
        maxDepth: Int = 8,
        maxVisibleElements: Int = 320
    ) -> [(element: AXUIElement, snapshot: ReplayElementSnapshot)] {
        guard depth <= maxDepth else {
            return []
        }

        var results: [(element: AXUIElement, snapshot: ReplayElementSnapshot)] = []
        if let snapshot = makeElementSnapshot(element: element, path: path) {
            results.append((element, snapshot))
        }

        if results.count >= maxVisibleElements {
            return results
        }

        let children = childElements(from: element)
        for (index, child) in children.enumerated() {
            let role = stringAttribute(kAXRoleAttribute as CFString, from: child) ?? "AXUnknown"
            let childPath = "\(path)/\(role)[\(index)]"
            results.append(contentsOf: enumerateElements(from: child, path: childPath, depth: depth + 1))
            if results.count >= maxVisibleElements {
                return Array(results.prefix(maxVisibleElements))
            }
        }

        return results
    }

    private func score(snapshot: ReplayElementSnapshot, candidate: ReplayElementSnapshot) -> Int {
        var value = 0
        if normalizedText(snapshot.identifier) == normalizedText(candidate.identifier),
           snapshot.identifier != nil {
            value += 8
        }
        if normalizedText(snapshot.title) == normalizedText(candidate.title),
           snapshot.title != nil {
            value += 4
        }
        if normalizedText(snapshot.role) == normalizedText(candidate.role),
           snapshot.role != nil {
            value += 2
        }
        if let lhs = snapshot.boundingRect,
           let rhs = candidate.boundingRect,
           overlapRatio(lhs: lhs, rhs: rhs) > 0.5 {
            value += 1
        }
        return value
    }

    private func overlapRatio(lhs: SemanticBoundingRect, rhs: SemanticBoundingRect) -> Double {
        let lhsRect = CGRect(x: lhs.x, y: lhs.y, width: lhs.width, height: lhs.height)
        let rhsRect = CGRect(x: rhs.x, y: rhs.y, width: rhs.width, height: rhs.height)
        let intersection = lhsRect.intersection(rhsRect)
        guard !intersection.isNull else {
            return 0
        }
        let smallerArea = max(min(lhsRect.width * lhsRect.height, rhsRect.width * rhsRect.height), 1)
        return Double(intersection.width * intersection.height) / Double(smallerArea)
    }

    private func childElements(from element: AXUIElement) -> [AXUIElement] {
        let attributes: [CFString] = [
            kAXChildrenAttribute as CFString,
            "AXVisibleChildren" as CFString
        ]

        var results: [AXUIElement] = []
        var seen = Set<String>()
        for attribute in attributes {
            let children = axElementArrayAttribute(attribute, from: element)
            for child in children {
                let key = [
                    stringAttribute(kAXRoleAttribute as CFString, from: child) ?? "",
                    stringAttribute("AXIdentifier" as CFString, from: child) ?? "",
                    stringAttribute(kAXTitleAttribute as CFString, from: child) ?? "",
                    rectKey(boundingRect(from: child))
                ].joined(separator: "|")
                guard !seen.contains(key) else {
                    continue
                }
                seen.insert(key)
                results.append(child)
            }
        }
        return results
    }

    private func makeElementSnapshot(element: AXUIElement, path: String?) -> ReplayElementSnapshot? {
        let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: element)
        let title = stringAttribute(kAXTitleAttribute as CFString, from: element)
        let identifier = stringAttribute("AXIdentifier" as CFString, from: element)
        let descriptionText = stringAttribute(kAXDescriptionAttribute as CFString, from: element)
        let helpText = stringAttribute(kAXHelpAttribute as CFString, from: element)
        let boundingRect = boundingRect(from: element)

        if role == nil,
           subrole == nil,
           title == nil,
           identifier == nil,
           descriptionText == nil,
           helpText == nil,
           boundingRect == nil {
            return nil
        }

        return ReplayElementSnapshot(
            axPath: path,
            role: role,
            subrole: subrole,
            title: title,
            identifier: identifier,
            descriptionText: descriptionText,
            helpText: helpText,
            boundingRect: boundingRect
        )
    }

    private func axElementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func axElementArrayAttribute(_ attribute: CFString, from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let array = value as? [Any] else {
            return []
        }
        return array.compactMap {
            guard CFGetTypeID($0 as CFTypeRef) == AXUIElementGetTypeID() else {
                return nil
            }
            return ($0 as! AXUIElement)
        }
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else {
            return nil
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return value as? String
    }

    private func pointAttribute(_ attribute: CFString, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetType(value as! AXValue) == .cgPoint,
              AXValueGetValue(value as! AXValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func sizeAttribute(_ attribute: CFString, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetType(value as! AXValue) == .cgSize,
              AXValueGetValue(value as! AXValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func boundingRect(from element: AXUIElement) -> SemanticBoundingRect? {
        guard let position = pointAttribute(kAXPositionAttribute as CFString, from: element),
              let size = sizeAttribute(kAXSizeAttribute as CFString, from: element) else {
            return nil
        }
        return SemanticBoundingRect(x: position.x, y: position.y, width: size.width, height: size.height)
    }

    private func buildWindowSignature(
        windowElement: AXUIElement,
        appBundleId: String,
        windowTitle: String?
    ) -> WindowSignature? {
        let role = stringAttribute(kAXRoleAttribute as CFString, from: windowElement)
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: windowElement)
        let normalizedTitle = normalizedText(windowTitle)
        let sizeBucket = sizeBucket(for: boundingRect(from: windowElement))
        let signatureInput = [
            appBundleId,
            role ?? "",
            subrole ?? "",
            normalizedTitle ?? "",
            sizeBucket ?? ""
        ].joined(separator: "|")
        guard !signatureInput.isEmpty else {
            return nil
        }

        let digest = SHA256.hash(data: Data(signatureInput.utf8))
        let signature = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return WindowSignature(
            signature: signature,
            normalizedTitle: normalizedTitle,
            role: role,
            subrole: subrole,
            sizeBucket: sizeBucket
        )
    }

    private func sizeBucket(for rect: SemanticBoundingRect?) -> String? {
        guard let rect else {
            return nil
        }
        let widthBucket = max(Int(rect.width / 100), 1)
        let heightBucket = max(Int(rect.height / 100), 1)
        return "\(widthBucket)x\(heightBucket)"
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).lowercased()
    }

    private func rectKey(_ rect: SemanticBoundingRect?) -> String {
        guard let rect else {
            return ""
        }
        return "\(rect.x.rounded())|\(rect.y.rounded())|\(rect.width.rounded())|\(rect.height.rounded())"
    }

    private func modifierFlags(from modifiers: [String]) -> CGEventFlags {
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

    private func keyCode(for key: String) -> CGKeyCode? {
        switch key.lowercased() {
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
        case "return", "enter": return 36
        case "tab": return 48
        case "space": return 49
        case "delete", "backspace": return 51
        case "escape", "esc": return 53
        default:
            return nil
        }
    }
}

private struct ShortcutSpec {
    let modifiers: [String]
    let key: String
    let raw: String

    init?(keys: [String]) {
        let normalized = keys
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard let key = normalized.last else {
            return nil
        }
        self.modifiers = Array(normalized.dropLast())
        self.key = key
        self.raw = normalized.joined(separator: "+")
    }
}
