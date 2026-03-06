// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenStaffMacOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenStaffApp", targets: ["OpenStaffApp"])
    ],
    targets: [
        .executableTarget(
            name: "OpenStaffApp",
            path: "Sources/OpenStaffApp"
        )
    ]
)
