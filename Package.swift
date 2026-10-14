// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MediaPicker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MediaPicker", path: "Sources/MediaPicker")
    ]
)
