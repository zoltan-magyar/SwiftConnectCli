// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SwiftConnectCli",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "OpenConnectKit", targets: ["OpenConnectKit"]),
    .executable(name: "swiftconnect-cli", targets: ["SwiftConnectCli"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    //.package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.0"),
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
    // Swift library wrapping OpenConnect with Swift-native API
    .target(
      name: "OpenConnectKit",
      dependencies: ["COpenConnect"],
      exclude: ["VpnSession+Async.swift"]
    ),
    .executableTarget(
      name: "SwiftConnectCli",
      dependencies: [
        "OpenConnectKit",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
  ]
)

