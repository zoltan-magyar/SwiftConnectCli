// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftConnectCli",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "swiftconnect-cli", targets: ["SwiftConnectCli"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        // Minimal system library wrapper for OpenConnect
        .systemLibrary(
            name: "COpenConnectLib",
            pkgConfig: "openconnect",
            providers: [
                .brew(["openconnect"]),
                .apt(["libopenconnect-dev"]),
            ]
        ),
        // C wrapper target for shims that depend on OpenConnect
        .target(
            name: "COpenConnect",
            dependencies: ["COpenConnectLib"]
        ),
        .executableTarget(
            name: "SwiftConnectCli",
            dependencies: [
                "COpenConnect",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
