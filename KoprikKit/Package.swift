// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KoprikKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "KoprikKit", targets: ["KoprikKit"]),
        .executable(name: "koprik", targets: ["koprik"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "KoprikKit"),
        .executableTarget(
            name: "koprik",
            dependencies: [
                "KoprikKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "KoprikKitTests", dependencies: ["KoprikKit"]),
    ],
    swiftLanguageModes: [.v6]
)
