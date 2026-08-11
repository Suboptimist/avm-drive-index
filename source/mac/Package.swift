// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DriveIndexApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DriveIndexApp",
            path: "Sources/DriveIndexApp"
        )
    ]
)
