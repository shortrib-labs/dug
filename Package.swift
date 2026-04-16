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
        .systemLibrary(
            name: "CResolv",
            path: "Sources/CResolv"
        ),
        .executableTarget(
            name: "dug",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "CResolv"
            ],
            swiftSettings: [
                .unsafeFlags(["-O"], .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "dugTests",
            dependencies: ["dug"]
        )
    ]
)
