// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "OpenConnectKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OpenConnectKit", targets: ["OpenConnectKit"])
    ],
    targets: [
        .systemLibrary(
            name: "COpenConnectLib",
            pkgConfig: "openconnect",
            providers: [
                .brew(["openconnect"]),
                .apt(["libopenconnect-dev"]),
            ]
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
