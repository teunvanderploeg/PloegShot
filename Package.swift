// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PloegShot",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PloegShot", targets: ["PloegShot"])],
    targets: [
        .executableTarget(
            name: "PloegShot",
            path: "Sources/PloegShot",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PloegShotTests",
            dependencies: ["PloegShot"],
            path: "Tests/PloegShotTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
