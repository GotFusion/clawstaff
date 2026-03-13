import Foundation

public struct SemanticTarget: Codable, Equatable {
    public let locatorType: SemanticLocatorType
    public let appBundleId: String
    public let windowTitlePattern: String?
    public let windowSignature: String?
    public let elementRole: String?
    public let elementTitle: String?
    public let elementIdentifier: String?
    public let axPath: String?
    public let textAnchor: String?
    public let imageAnchor: SemanticImageAnchor?
    public let boundingRect: SemanticBoundingRect?
    public let confidence: Double
    public let source: SemanticTargetSource

    public init(
        locatorType: SemanticLocatorType,
        appBundleId: String,
        windowTitlePattern: String? = nil,
        windowSignature: String? = nil,
        elementRole: String? = nil,
        elementTitle: String? = nil,
        elementIdentifier: String? = nil,
        axPath: String? = nil,
        textAnchor: String? = nil,
        imageAnchor: SemanticImageAnchor? = nil,
        boundingRect: SemanticBoundingRect? = nil,
        confidence: Double,
        source: SemanticTargetSource
    ) {
        self.locatorType = locatorType
        self.appBundleId = appBundleId
        self.windowTitlePattern = windowTitlePattern
        self.windowSignature = windowSignature
        self.elementRole = elementRole
        self.elementTitle = elementTitle
        self.elementIdentifier = elementIdentifier
        self.axPath = axPath
        self.textAnchor = textAnchor
        self.imageAnchor = imageAnchor
        self.boundingRect = boundingRect
        self.confidence = confidence
        self.source = source
    }

    public static func coordinateFallback(
        appBundleId: String,
        windowTitle: String?,
        windowSignature: String? = nil,
        coordinate: PointerLocation,
        confidence: Double = 0.24,
        source: SemanticTargetSource = .capture
    ) -> SemanticTarget {
        SemanticTarget(
            locatorType: .coordinateFallback,
            appBundleId: appBundleId,
            windowTitlePattern: exactWindowTitlePattern(for: windowTitle),
            windowSignature: windowSignature,
            boundingRect: SemanticBoundingRect(
                x: Double(coordinate.x),
                y: Double(coordinate.y),
                width: 1,
                height: 1,
                coordinateSpace: .screen
            ),
            confidence: confidence,
            source: source
        )
    }

    public static func exactWindowTitlePattern(for windowTitle: String?) -> String? {
        guard let windowTitle,
              !windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return "^\(NSRegularExpression.escapedPattern(for: windowTitle))$"
    }
}

public enum SemanticLocatorType: String, Codable {
    case axPath
    case roleAndTitle
    case textAnchor
    case imageAnchor
    case coordinateFallback
}

public enum SemanticTargetSource: String, Codable {
    case capture
    case inferred
    case repaired
}

public struct SemanticImageAnchor: Codable, Equatable {
    public let pixelHash: String
    public let averageLuma: Double
    public let sampleWidth: Int?
    public let sampleHeight: Int?

    public init(
        pixelHash: String,
        averageLuma: Double,
        sampleWidth: Int? = nil,
        sampleHeight: Int? = nil
    ) {
        self.pixelHash = pixelHash
        self.averageLuma = averageLuma
        self.sampleWidth = sampleWidth
        self.sampleHeight = sampleHeight
    }
}

public struct SemanticBoundingRect: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let coordinateSpace: SemanticCoordinateSpace

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        coordinateSpace: SemanticCoordinateSpace = .screen
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.coordinateSpace = coordinateSpace
    }
}

public enum SemanticCoordinateSpace: String, Codable {
    case screen
}
