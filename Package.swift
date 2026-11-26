// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DevicePreview",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DevicePreview",
            path: "Sources/DevicePreview"
        )
    ]
)
