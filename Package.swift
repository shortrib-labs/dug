// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "dug",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "dug", targets: ["dug"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0")
    ],
    targets: [
        .executableTarget(
            name: "dug",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: [
                .unsafeFlags(["-Osize"], .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "dugTests",
            dependencies: ["dug"]
        )
    ]
)
