// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "OpenConnectKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OpenConnectKit", targets: ["OpenConnectKit"])
    ],
    targets: [
        .binaryTarget(
            name: "COpenConnectLib",
            path: "Frameworks/OpenConnectC.xcframework"
        ),
        .target(
            name: "COpenConnect",
            dependencies: ["COpenConnectLib"]
        ),
        .target(
            name: "OpenConnectKit",
            dependencies: ["COpenConnect"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        ),
    ]
)
