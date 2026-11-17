// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SidecarDash",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SidecarDash", path: "Sources/SidecarDash")
    ]
)
