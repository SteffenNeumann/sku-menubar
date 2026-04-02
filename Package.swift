// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SKUMenuBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/raspu/Highlightr", from: "2.1.2")
    ],
    targets: [
        .executableTarget(
            name: "myClaude",
            dependencies: [
                .product(name: "Highlightr", package: "Highlightr")
            ],
            path: "Sources/SKUMenuBar",
            resources: [
                .process("Assets.xcassets"),
                .process("AgentPortraits")
            ]
        )
    ]
)
