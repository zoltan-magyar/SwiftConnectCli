// swift-tools-version: 6.2.3
import PackageDescription

let package = Package(
  name: "SwiftConnectCli",
  platforms: [.macOS(.v26)],
  products: [
    .executable(name: "swiftconnect-cli", targets: ["SwiftConnectCli"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    .package(path: "../OpenConnectKit"),
    //.package(url: "https://github.com/zoltan-magyar/OpenConnectKit.git"),
  ],
  targets: [
    .executableTarget(
      name: "SwiftConnectCli",
      dependencies: [
        .product(name: "OpenConnectKit", package: "OpenConnectKit"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("NonisolatedNonsendingByDefault")
      ]
    )
  ]
)
