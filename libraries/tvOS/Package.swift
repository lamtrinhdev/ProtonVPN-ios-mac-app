// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "tvOS",
    defaultLocalization: "en",
    platforms: [
        .tvOS(.v17)
    ],
    products: [
        .library(
            name: "tvOS",
            targets: ["tvOS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.10.2"),
        .package(path: "../../external/protoncore"),
        .package(path: "../Shared/CommonNetworking"),
        .package(path: "../Shared/Persistence"),
        .package(path: "../Foundations/Theme"),
    ],
    targets: [
        .target(
            name: "tvOS",
            dependencies: [
                "Theme",
                "CommonNetworking",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Persistence", package: "Persistence"),
                .core(module: "ForceUpgrade"),
                .core(module: "Networking"),
                .core(module: "UIFoundations"),
                .core(module: "Services")
            ],
            resources: [
                .process("Resources/Assets.xcassets")
            ]),
        .testTarget(
            name: "tvOSTests",
            dependencies: [
                "tvOS",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]),
    ]
)

extension PackageDescription.Target.Dependency {
    static func core(module: String) -> Self {
        .product(name: "ProtonCore\(module)", package: "protoncore")
    }
}
