// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "dug",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "dug", targets: ["dug"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0")
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
                .product(name: "Yams", package: "Yams"),
                "CResolv"
            ]
        ),
        .testTarget(
            name: "dugTests",
            dependencies: [
                "dug",
                .product(name: "Yams", package: "Yams")
            ]
        )
    ]
)
