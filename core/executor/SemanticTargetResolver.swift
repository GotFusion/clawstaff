import AppKit
import ApplicationServices
import CoreGraphics
import CryptoKit
import Foundation

public struct ReplayElementSnapshot: Codable, Equatable {
    public let axPath: String?
    public let role: String?
    public let subrole: String?
    public let title: String?
    public let identifier: String?
    public let descriptionText: String?
    public let helpText: String?
    public let boundingRect: SemanticBoundingRect?

    public init(
        axPath: String? = nil,
        role: String? = nil,
        subrole: String? = nil,
        title: String? = nil,
        identifier: String? = nil,
        descriptionText: String? = nil,
        helpText: String? = nil,
        boundingRect: SemanticBoundingRect? = nil
    ) {
        self.axPath = axPath
        self.role = role
        self.subrole = subrole
        self.title = title
        self.identifier = identifier
        self.descriptionText = descriptionText
        self.helpText = helpText
        self.boundingRect = boundingRect
    }
}

public struct ReplayEnvironmentSnapshot: Codable, Equatable {
    public let capturedAt: String
    public let appName: String
    public let appBundleId: String
    public let windowTitle: String?
    public let windowId: String?
    public let windowSignature: WindowSignature?
    public let focusedElement: ReplayElementSnapshot?
    public let visibleElements: [ReplayElementSnapshot]
    public let screenshotAnchors: [ScreenshotAnchor]
    public let captureDiagnostics: [ContextCaptureDiagnostic]

    public init(
        capturedAt: String,
        appName: String,
        appBundleId: String,
        windowTitle: String? = nil,
        windowId: String? = nil,
        windowSignature: WindowSignature? = nil,
        focusedElement: ReplayElementSnapshot? = nil,
        visibleElements: [ReplayElementSnapshot] = [],
        screenshotAnchors: [ScreenshotAnchor] = [],
        captureDiagnostics: [ContextCaptureDiagnostic] = []
    ) {
        self.capturedAt = capturedAt
        self.appName = appName
        self.appBundleId = appBundleId
        self.windowTitle = windowTitle
        self.windowId = windowId
        self.windowSignature = windowSignature
        self.focusedElement = focusedElement
        self.visibleElements = visibleElements
        self.screenshotAnchors = screenshotAnchors
        self.captureDiagnostics = captureDiagnostics
    }
}

public protocol ReplayEnvironmentSnapshotProviding {
    func snapshot() -> ReplayEnvironmentSnapshot
}

public struct StaticReplayEnvironmentSnapshotProvider: ReplayEnvironmentSnapshotProviding {
    private let value: ReplayEnvironmentSnapshot

    public init(snapshot: ReplayEnvironmentSnapshot) {
        self.value = snapshot
    }

    public func snapshot() -> ReplayEnvironmentSnapshot {
        value
    }
}

public enum SemanticTargetResolutionStatus: String, Codable {
    case resolved
    case degraded
    case unresolved
}

public enum SemanticTargetFailureReason: String, Codable {
    case noSemanticTargets
    case captureUnavailable
    case appMismatch
    case windowMismatch
    case elementMissing
    case textAnchorChanged
    case imageAnchorChanged
    case coordinateFallbackOnly
}

public struct SemanticTargetResolutionAttempt: Codable, Equatable {
    public let locatorType: SemanticLocatorType
    public let status: SemanticTargetResolutionStatus
    public let failureReason: SemanticTargetFailureReason?
    public let message: String
    public let matchedElement: ReplayElementSnapshot?

    public init(
        locatorType: SemanticLocatorType,
        status: SemanticTargetResolutionStatus,
        failureReason: SemanticTargetFailureReason?,
        message: String,
        matchedElement: ReplayElementSnapshot? = nil
    ) {
        self.locatorType = locatorType
        self.status = status
        self.failureReason = failureReason
        self.message = message
        self.matchedElement = matchedElement
    }
}

public struct SemanticTargetResolution: Codable, Equatable {
    public let status: SemanticTargetResolutionStatus
    public let matchedLocatorType: SemanticLocatorType?
    public let failureReason: SemanticTargetFailureReason?
    public let message: String
    public let matchedElement: ReplayElementSnapshot?
    public let attempts: [SemanticTargetResolutionAttempt]

    public init(
        status: SemanticTargetResolutionStatus,
        matchedLocatorType: SemanticLocatorType? = nil,
        failureReason: SemanticTargetFailureReason? = nil,
        message: String,
        matchedElement: ReplayElementSnapshot? = nil,
        attempts: [SemanticTargetResolutionAttempt]
    ) {
        self.status = status
        self.matchedLocatorType = matchedLocatorType
        self.failureReason = failureReason
        self.message = message
        self.matchedElement = matchedElement
        self.attempts = attempts
    }
}

public protocol SemanticScreenFingerprintCapturing {
    func capture(rect: SemanticBoundingRect) -> SemanticImageAnchor?
}

public struct SemanticTargetResolver {
    private let fingerprintCapture: any SemanticScreenFingerprintCapturing
    private let imageAnchorLumaTolerance: Double

    public init(
        fingerprintCapture: any SemanticScreenFingerprintCapturing = LiveSemanticScreenFingerprintCapture(),
        imageAnchorLumaTolerance: Double = 0.035
    ) {
        self.fingerprintCapture = fingerprintCapture
        self.imageAnchorLumaTolerance = imageAnchorLumaTolerance
    }

    public func resolve(
        targets: [SemanticTarget],
        preferredLocatorType: SemanticLocatorType? = nil,
        coordinate: PointerLocation? = nil,
        in snapshot: ReplayEnvironmentSnapshot
    ) -> SemanticTargetResolution {
        let orderedTargets = orderedTargets(from: targets, preferredLocatorType: preferredLocatorType)

        guard !orderedTargets.isEmpty else {
            if coordinate != nil,
               appAndWindowCompatible(target: nil, snapshot: snapshot) {
                let attempt = SemanticTargetResolutionAttempt(
                    locatorType: .coordinateFallback,
                    status: .degraded,
                    failureReason: .coordinateFallbackOnly,
                    message: "仅能使用旧坐标回退，缺少可验证的语义定位。"
                )
                return SemanticTargetResolution(
                    status: .degraded,
                    matchedLocatorType: .coordinateFallback,
                    failureReason: .coordinateFallbackOnly,
                    message: attempt.message,
                    attempts: [attempt]
                )
            }

            return SemanticTargetResolution(
                status: .unresolved,
                failureReason: .noSemanticTargets,
                message: "步骤缺少语义定位目标，无法执行 dry-run 验证。",
                attempts: [
                    SemanticTargetResolutionAttempt(
                        locatorType: .coordinateFallback,
                        status: .unresolved,
                        failureReason: .noSemanticTargets,
                        message: "未提供任何 semanticTargets。"
                    )
                ]
            )
        }

        let candidates = collectCandidates(from: snapshot)
        var attempts: [SemanticTargetResolutionAttempt] = []

        for target in orderedTargets {
            if target.appBundleId != snapshot.appBundleId {
                attempts.append(
                    SemanticTargetResolutionAttempt(
                        locatorType: target.locatorType,
                        status: .unresolved,
                        failureReason: .appMismatch,
                        message: "前台应用不匹配。expected=\(target.appBundleId) actual=\(snapshot.appBundleId)"
                    )
                )
                continue
            }

            if !windowMatches(target: target, snapshot: snapshot) {
                attempts.append(
                    SemanticTargetResolutionAttempt(
                        locatorType: target.locatorType,
                        status: .unresolved,
                        failureReason: .windowMismatch,
                        message: "窗口不匹配，未通过标题模式或窗口签名校验。"
                    )
                )
                continue
            }

            let attempt = resolveTarget(
                target,
                coordinate: coordinate,
                candidates: candidates,
                snapshot: snapshot
            )
            attempts.append(attempt)

            switch attempt.status {
            case .resolved, .degraded:
                return SemanticTargetResolution(
                    status: attempt.status,
                    matchedLocatorType: target.locatorType,
                    failureReason: attempt.failureReason,
                    message: attempt.message,
                    matchedElement: attempt.matchedElement,
                    attempts: attempts
                )
            case .unresolved:
                break
            }
        }

        let finalFailureReason = attempts.last(where: { $0.failureReason != nil })?.failureReason ?? .elementMissing
        let finalMessage = attempts.last?.message ?? "未找到任何可解析目标。"
        return SemanticTargetResolution(
            status: .unresolved,
            failureReason: finalFailureReason,
            message: finalMessage,
            attempts: attempts
        )
    }

    private func resolveTarget(
        _ target: SemanticTarget,
        coordinate: PointerLocation?,
        candidates: [ReplayElementSnapshot],
        snapshot: ReplayEnvironmentSnapshot
    ) -> SemanticTargetResolutionAttempt {
        switch target.locatorType {
        case .axPath:
            guard let axPath = normalizedAxPath(target.axPath) else {
                return SemanticTargetResolutionAttempt(
                    locatorType: .axPath,
                    status: .unresolved,
                    failureReason: .elementMissing,
                    message: "axPath locator 缺少 path 信息。"
                )
            }

            guard let matched = candidates.first(where: { normalizedAxPath($0.axPath) == axPath }) else {
                return SemanticTargetResolutionAttempt(
                    locatorType: .axPath,
                    status: .unresolved,
                    failureReason: .elementMissing,
                    message: "未在当前窗口 AX 树中找到匹配的 axPath。"
                )
            }

            return SemanticTargetResolutionAttempt(
                locatorType: .axPath,
                status: .resolved,
                failureReason: nil,
                message: "通过 axPath 找到目标。",
                matchedElement: matched
            )

        case .roleAndTitle:
            guard let matched = bestRoleAndTitleMatch(for: target, candidates: candidates) else {
                return SemanticTargetResolutionAttempt(
                    locatorType: .roleAndTitle,
                    status: .unresolved,
                    failureReason: .elementMissing,
                    message: "未找到匹配的 role/title/identifier 元素。"
                )
            }

            return SemanticTargetResolutionAttempt(
                locatorType: .roleAndTitle,
                status: .resolved,
                failureReason: nil,
                message: "通过 roleAndTitle 找到目标。",
                matchedElement: matched
            )

        case .textAnchor:
            let textAnchor = normalizedText(target.textAnchor ?? target.elementTitle)
            guard let textAnchor, !textAnchor.isEmpty else {
                return SemanticTargetResolutionAttempt(
                    locatorType: .textAnchor,
                    status: .unresolved,
                    failureReason: .elementMissing,
                    message: "textAnchor locator 缺少 anchor 文本。"
                )
            }

            if let matched = candidates.first(where: { searchableText(for: $0).contains(textAnchor) }) {
                return SemanticTargetResolutionAttempt(
                    locatorType: .textAnchor,
                    status: .resolved,
                    failureReason: nil,
                    message: "通过 textAnchor 找到目标。",
                    matchedElement: matched
                )
            }

            let hasNearbyCandidate = candidates.contains { candidate in
                roleMatches(target: target, candidate: candidate) || identifierMatches(target: target, candidate: candidate)
            }

            return SemanticTargetResolutionAttempt(
                locatorType: .textAnchor,
                status: .unresolved,
                failureReason: hasNearbyCandidate ? .textAnchorChanged : .elementMissing,
                message: hasNearbyCandidate ? "找到结构相近元素，但文本锚点已变化。" : "未找到包含文本锚点的元素。"
            )

        case .imageAnchor:
            guard let imageAnchor = target.imageAnchor,
                  let boundingRect = target.boundingRect else {
                return SemanticTargetResolutionAttempt(
                    locatorType: .imageAnchor,
                    status: .unresolved,
                    failureReason: .elementMissing,
                    message: "imageAnchor locator 缺少截图指纹或矩形范围。"
                )
            }

            if let matchedAnchor = snapshot.screenshotAnchors.first(where: { screenshotAnchorMatches(imageAnchor: imageAnchor, targetRect: boundingRect, anchor: $0) }) {
                return SemanticTargetResolutionAttempt(
                    locatorType: .imageAnchor,
                    status: .resolved,
                    failureReason: nil,
                    message: "通过离线 screenshotAnchor 匹配到目标。anchorHash=\(matchedAnchor.pixelHash)"
                )
            }

            if let liveAnchor = fingerprintCapture.capture(rect: boundingRect),
               imageAnchorMatches(lhs: imageAnchor, rhs: liveAnchor) {
                return SemanticTargetResolutionAttempt(
                    locatorType: .imageAnchor,
                    status: .resolved,
                    failureReason: nil,
                    message: "通过实时截图指纹匹配到目标。"
                )
            }

            let captureUnavailable = snapshot.captureDiagnostics.contains(where: { $0.code.hasPrefix("CTX-SCREENSHOT-") })
            return SemanticTargetResolutionAttempt(
                locatorType: .imageAnchor,
                status: .unresolved,
                failureReason: captureUnavailable ? .captureUnavailable : .imageAnchorChanged,
                message: captureUnavailable ? "当前环境缺少可用截图能力，无法验证 imageAnchor。" : "截图锚点已变化或无法复现。"
            )

        case .coordinateFallback:
            guard coordinate != nil || target.boundingRect != nil else {
                return SemanticTargetResolutionAttempt(
                    locatorType: .coordinateFallback,
                    status: .unresolved,
                    failureReason: .elementMissing,
                    message: "coordinateFallback 缺少坐标或矩形信息。"
                )
            }

            return SemanticTargetResolutionAttempt(
                locatorType: .coordinateFallback,
                status: .degraded,
                failureReason: .coordinateFallbackOnly,
                message: "只剩坐标回退，说明缺少可接受的语义定位命中。"
            )
        }
    }

    private func orderedTargets(
        from targets: [SemanticTarget],
        preferredLocatorType: SemanticLocatorType?
    ) -> [SemanticTarget] {
        targets.enumerated()
            .sorted { lhs, rhs in
                let lhsPriority = priority(for: lhs.element.locatorType, preferredLocatorType: preferredLocatorType)
                let rhsPriority = priority(for: rhs.element.locatorType, preferredLocatorType: preferredLocatorType)
                if lhsPriority == rhsPriority {
                    return lhs.offset < rhs.offset
                }
                return lhsPriority < rhsPriority
            }
            .map(\.element)
    }

    private func priority(
        for locatorType: SemanticLocatorType,
        preferredLocatorType: SemanticLocatorType?
    ) -> Int {
        let base: Int
        switch locatorType {
        case .axPath:
            base = 0
        case .roleAndTitle:
            base = 10
        case .textAnchor:
            base = 20
        case .imageAnchor:
            base = 30
        case .coordinateFallback:
            base = 40
        }

        guard preferredLocatorType == locatorType else {
            return base
        }
        return base - 1
    }

    private func collectCandidates(from snapshot: ReplayEnvironmentSnapshot) -> [ReplayElementSnapshot] {
        var candidates: [ReplayElementSnapshot] = []
        var seen = Set<String>()

        func append(_ candidate: ReplayElementSnapshot?) {
            guard let candidate else {
                return
            }

            let key = [
                candidate.axPath ?? "",
                candidate.identifier ?? "",
                candidate.title ?? "",
                rectKey(candidate.boundingRect)
            ].joined(separator: "|")

            guard !seen.contains(key) else {
                return
            }

            seen.insert(key)
            candidates.append(candidate)
        }

        append(snapshot.focusedElement)
        snapshot.visibleElements.forEach(append)
        return candidates
    }

    private func appAndWindowCompatible(target: SemanticTarget?, snapshot: ReplayEnvironmentSnapshot) -> Bool {
        guard let target else {
            return true
        }

        guard target.appBundleId == snapshot.appBundleId else {
            return false
        }

        return windowMatches(target: target, snapshot: snapshot)
    }

    private func windowMatches(target: SemanticTarget, snapshot: ReplayEnvironmentSnapshot) -> Bool {
        if let windowSignature = target.windowSignature,
           snapshot.windowSignature?.signature != windowSignature {
            return false
        }

        guard let pattern = target.windowTitlePattern else {
            return true
        }

        guard let windowTitle = snapshot.windowTitle else {
            return false
        }

        return windowTitle.range(of: pattern, options: .regularExpression) != nil
    }

    private func bestRoleAndTitleMatch(
        for target: SemanticTarget,
        candidates: [ReplayElementSnapshot]
    ) -> ReplayElementSnapshot? {
        var bestScore = Int.min
        var bestMatch: ReplayElementSnapshot?

        for candidate in candidates {
            guard roleMatches(target: target, candidate: candidate),
                  titleMatches(target: target, candidate: candidate),
                  identifierMatches(target: target, candidate: candidate) else {
                continue
            }

            let score = score(target: target, candidate: candidate)
            if score > bestScore {
                bestScore = score
                bestMatch = candidate
            }
        }

        return bestMatch
    }

    private func roleMatches(target: SemanticTarget, candidate: ReplayElementSnapshot) -> Bool {
        guard let role = normalizedText(target.elementRole) else {
            return true
        }

        return role == normalizedText(candidate.role)
            || role == normalizedText(candidate.subrole)
    }

    private func titleMatches(target: SemanticTarget, candidate: ReplayElementSnapshot) -> Bool {
        guard let title = normalizedText(target.elementTitle) else {
            return true
        }

        let candidateText = searchableText(for: candidate)
        return candidateText.contains(title)
    }

    private func identifierMatches(target: SemanticTarget, candidate: ReplayElementSnapshot) -> Bool {
        guard let identifier = normalizedText(target.elementIdentifier) else {
            return true
        }

        return normalizedText(candidate.identifier) == identifier
    }

    private func score(target: SemanticTarget, candidate: ReplayElementSnapshot) -> Int {
        var score = 0

        if let identifier = normalizedText(target.elementIdentifier),
           normalizedText(candidate.identifier) == identifier {
            score += 8
        }

        if let title = normalizedText(target.elementTitle),
           searchableText(for: candidate).contains(title) {
            score += 4
        }

        if let role = normalizedText(target.elementRole),
           role == normalizedText(candidate.role) || role == normalizedText(candidate.subrole) {
            score += 2
        }

        if let targetRect = target.boundingRect,
           let candidateRect = candidate.boundingRect,
           overlapRatio(lhs: targetRect, rhs: candidateRect) > 0.5 {
            score += 1
        }

        return score
    }

    private func searchableText(for candidate: ReplayElementSnapshot) -> String {
        [
            candidate.title,
            candidate.descriptionText,
            candidate.helpText
        ]
        .compactMap(normalizedText)
        .joined(separator: " ")
    }

    private func screenshotAnchorMatches(
        imageAnchor: SemanticImageAnchor,
        targetRect: SemanticBoundingRect,
        anchor: ScreenshotAnchor
    ) -> Bool {
        guard overlapRatio(lhs: targetRect, rhs: anchor.boundingRect) > 0.35 else {
            return false
        }

        let candidate = SemanticImageAnchor(
            pixelHash: anchor.pixelHash,
            averageLuma: anchor.averageLuma,
            sampleWidth: anchor.sampleSize.width,
            sampleHeight: anchor.sampleSize.height
        )
        return imageAnchorMatches(lhs: imageAnchor, rhs: candidate)
    }

    private func imageAnchorMatches(lhs: SemanticImageAnchor, rhs: SemanticImageAnchor) -> Bool {
        if lhs.pixelHash == rhs.pixelHash {
            return true
        }

        return abs(lhs.averageLuma - rhs.averageLuma) <= imageAnchorLumaTolerance
    }

    private func overlapRatio(lhs: SemanticBoundingRect, rhs: SemanticBoundingRect) -> Double {
        let lhsRect = CGRect(
            x: lhs.x,
            y: lhs.y,
            width: lhs.width,
            height: lhs.height
        )
        let rhsRect = CGRect(
            x: rhs.x,
            y: rhs.y,
            width: rhs.width,
            height: rhs.height
        )

        let intersection = lhsRect.intersection(rhsRect)
        guard !intersection.isNull else {
            return 0
        }

        let smallerArea = max(min(lhsRect.width * lhsRect.height, rhsRect.width * rhsRect.height), 1)
        return Double(intersection.width * intersection.height) / Double(smallerArea)
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    private func normalizedAxPath(_ value: String?) -> String? {
        normalizedText(value)?
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private func rectKey(_ rect: SemanticBoundingRect?) -> String {
        guard let rect else {
            return ""
        }

        return "\(rect.x.rounded())|\(rect.y.rounded())|\(rect.width.rounded())|\(rect.height.rounded())"
    }
}

public struct LiveReplayEnvironmentSnapshotProvider: ReplayEnvironmentSnapshotProviding {
    private let maxDepth: Int
    private let maxVisibleElements: Int
    private let nowProvider: () -> Date
    private let timestampFormatter: ISO8601DateFormatter

    public init(
        maxDepth: Int = 8,
        maxVisibleElements: Int = 320,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.maxDepth = maxDepth
        self.maxVisibleElements = maxVisibleElements
        self.nowProvider = nowProvider

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestampFormatter = formatter
    }

    public func snapshot() -> ReplayEnvironmentSnapshot {
        let builder = AXReplaySnapshotBuilder(
            maxDepth: maxDepth,
            maxVisibleElements: maxVisibleElements,
            capturedAt: timestampFormatter.string(from: nowProvider())
        )
        return builder.build()
    }
}

public struct LiveSemanticScreenFingerprintCapture: SemanticScreenFingerprintCapturing {
    public init() {}

    public func capture(rect: SemanticBoundingRect) -> SemanticImageAnchor? {
        guard hasScreenCapturePermission() else {
            return nil
        }

        let cgRect = CGRect(
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height
        )
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(cgRect) }),
              let displayID = displayID(for: screen) else {
            return nil
        }

        let boundedRect = cgRect.intersection(screen.frame)
        guard !boundedRect.isNull,
              boundedRect.width > 0,
              boundedRect.height > 0 else {
            return nil
        }

        let pixelRect = displayPixelRect(for: boundedRect, on: screen)
        guard let image = CGDisplayCreateImage(displayID, rect: pixelRect),
              let fingerprint = fingerprint(for: image) else {
            return nil
        }

        return SemanticImageAnchor(
            pixelHash: fingerprint.hash,
            averageLuma: fingerprint.averageLuma,
            sampleWidth: image.width,
            sampleHeight: image.height
        )
    }

    private func hasScreenCapturePermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }

    private func displayPixelRect(for screenRect: CGRect, on screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        let scale = screen.backingScaleFactor
        let localRect = CGRect(
            x: screenRect.origin.x - screenFrame.origin.x,
            y: screenRect.origin.y - screenFrame.origin.y,
            width: screenRect.width,
            height: screenRect.height
        )

        return CGRect(
            x: localRect.origin.x * scale,
            y: (screenFrame.height - localRect.maxY) * scale,
            width: localRect.width * scale,
            height: localRect.height * scale
        )
    }

    private func fingerprint(for image: CGImage) -> (hash: String, averageLuma: Double)? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var totalLuma = 0.0
        for index in stride(from: 0, to: bytes.count, by: bytesPerPixel) {
            let red = Double(bytes[index])
            let green = Double(bytes[index + 1])
            let blue = Double(bytes[index + 2])
            totalLuma += (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        }

        let averageLuma = ((totalLuma / Double(width * height)) / 255.0 * 1_000).rounded() / 1_000
        let digest = SHA256.hash(data: Data(bytes))
        let hash = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return (hash, averageLuma)
    }
}

private struct AXReplaySnapshotBuilder {
    let maxDepth: Int
    let maxVisibleElements: Int
    let capturedAt: String

    func build() -> ReplayEnvironmentSnapshot {
        var diagnostics: [ContextCaptureDiagnostic] = []

        guard let app = NSWorkspace.shared.frontmostApplication else {
            diagnostics.append(
                ContextCaptureDiagnostic(
                    code: "CTX-FRONTMOST-APP-UNAVAILABLE",
                    field: "app",
                    message: "无法解析当前前台应用。"
                )
            )

            return ReplayEnvironmentSnapshot(
                capturedAt: capturedAt,
                appName: "Unknown",
                appBundleId: "unknown.bundle.id",
                captureDiagnostics: diagnostics
            )
        }

        let appName = app.localizedName ?? "Unknown"
        let appBundleId = app.bundleIdentifier ?? "unknown.bundle.id"
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        let windowElement = axElementAttribute(kAXFocusedWindowAttribute as CFString, from: appElement)
        if windowElement == nil {
            diagnostics.append(
                ContextCaptureDiagnostic(
                    code: "CTX-AX-WINDOW-UNAVAILABLE",
                    field: "windowContext",
                    message: "无法读取当前聚焦窗口。"
                )
            )
        }

        let windowTitle = windowElement.flatMap { stringAttribute(kAXTitleAttribute as CFString, from: $0) }
        let windowId = windowElement.flatMap { stringAttribute("AXWindowNumber" as CFString, from: $0) }
        let windowSignature = windowElement.flatMap {
            buildWindowSignature(windowElement: $0, appBundleId: appBundleId, windowTitle: windowTitle)
        }

        let focusedElement = axElementAttribute(kAXFocusedUIElementAttribute as CFString, from: appElement)
        if focusedElement == nil {
            diagnostics.append(
                ContextCaptureDiagnostic(
                    code: "CTX-AX-FOCUSED-ELEMENT-UNAVAILABLE",
                    field: "focusedElement",
                    message: "无法读取当前焦点元素。"
                )
            )
        }

        var visibleElements: [ReplayElementSnapshot] = []
        if let windowElement {
            let rootRole = stringAttribute(kAXRoleAttribute as CFString, from: windowElement) ?? "AXWindow"
            enumerateElements(
                from: windowElement,
                path: rootRole,
                depth: 0,
                accumulator: &visibleElements
            )
        }

        let focusedSnapshot = focusedElement.flatMap { element in
            makeElementSnapshot(
                element: element,
                path: windowElement.flatMap { findPath(to: element, from: $0) }
            )
        }

        return ReplayEnvironmentSnapshot(
            capturedAt: capturedAt,
            appName: appName,
            appBundleId: appBundleId,
            windowTitle: windowTitle,
            windowId: windowId,
            windowSignature: windowSignature,
            focusedElement: focusedSnapshot,
            visibleElements: visibleElements,
            captureDiagnostics: diagnostics
        )
    }

    private func enumerateElements(
        from element: AXUIElement,
        path: String,
        depth: Int,
        accumulator: inout [ReplayElementSnapshot]
    ) {
        guard accumulator.count < maxVisibleElements, depth <= maxDepth else {
            return
        }

        if let snapshot = makeElementSnapshot(element: element, path: path) {
            accumulator.append(snapshot)
        }

        let children = childElements(from: element)
        for (index, child) in children.enumerated() {
            guard accumulator.count < maxVisibleElements else {
                return
            }

            let role = stringAttribute(kAXRoleAttribute as CFString, from: child) ?? "AXUnknown"
            enumerateElements(
                from: child,
                path: "\(path)/\(role)[\(index)]",
                depth: depth + 1,
                accumulator: &accumulator
            )
        }
    }

    private func findPath(to target: AXUIElement, from root: AXUIElement) -> String? {
        let rootRole = stringAttribute(kAXRoleAttribute as CFString, from: root) ?? "AXWindow"

        if CFEqual(root, target) {
            return rootRole
        }

        return findPath(
            to: target,
            from: root,
            currentPath: rootRole,
            depth: 0
        )
    }

    private func findPath(
        to target: AXUIElement,
        from current: AXUIElement,
        currentPath: String,
        depth: Int
    ) -> String? {
        guard depth <= maxDepth else {
            return nil
        }

        let children = childElements(from: current)
        for (index, child) in children.enumerated() {
            let role = stringAttribute(kAXRoleAttribute as CFString, from: child) ?? "AXUnknown"
            let childPath = "\(currentPath)/\(role)[\(index)]"

            if CFEqual(child, target) {
                return childPath
            }

            if let found = findPath(
                to: target,
                from: child,
                currentPath: childPath,
                depth: depth + 1
            ) {
                return found
            }
        }

        return nil
    }

    private func makeElementSnapshot(
        element: AXUIElement,
        path: String?
    ) -> ReplayElementSnapshot? {
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
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetType(axValue as! AXValue) == .cgPoint,
              AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func sizeAttribute(_ attribute: CFString, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetType(axValue as! AXValue) == .cgSize,
              AXValueGetValue(axValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func boundingRect(from element: AXUIElement) -> SemanticBoundingRect? {
        guard let position = pointAttribute(kAXPositionAttribute as CFString, from: element),
              let size = sizeAttribute(kAXSizeAttribute as CFString, from: element) else {
            return nil
        }

        return SemanticBoundingRect(
            x: position.x,
            y: position.y,
            width: size.width,
            height: size.height,
            coordinateSpace: .screen
        )
    }

    private func buildWindowSignature(
        windowElement: AXUIElement,
        appBundleId: String,
        windowTitle: String?
    ) -> WindowSignature? {
        let role = stringAttribute(kAXRoleAttribute as CFString, from: windowElement)
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: windowElement)
        let normalizedTitle = normalizedWindowTitle(windowTitle)
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

    private func normalizedWindowTitle(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    private func sizeBucket(for rect: SemanticBoundingRect?) -> String? {
        guard let rect else {
            return nil
        }

        let widthBucket = max(Int(rect.width.rounded() / 100), 1)
        let heightBucket = max(Int(rect.height.rounded() / 100), 1)
        return "\(widthBucket)x\(heightBucket)"
    }

    private func rectKey(_ rect: SemanticBoundingRect?) -> String {
        guard let rect else {
            return ""
        }

        return "\(rect.x.rounded())|\(rect.y.rounded())|\(rect.width.rounded())|\(rect.height.rounded())"
    }
}
