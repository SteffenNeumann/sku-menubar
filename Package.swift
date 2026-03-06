// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SKUMenuBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SKUMenuBar",
            path: "Sources/SKUMenuBar"
        )
    ]
)
