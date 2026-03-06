// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenStaffMacOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenStaffApp", targets: ["OpenStaffApp"]),
        .executable(name: "OpenStaffCaptureCLI", targets: ["OpenStaffCaptureCLI"])
    ],
    targets: [
        .executableTarget(
            name: "OpenStaffApp",
            path: "Sources/OpenStaffApp"
        ),
        .executableTarget(
            name: "OpenStaffCaptureCLI",
            path: "Sources/OpenStaffCaptureCLI"
        )
    ]
)
