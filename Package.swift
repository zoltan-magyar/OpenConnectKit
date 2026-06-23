// swift-tools-version: 6.3
import PackageDescription

#if os(Linux)
let cOpenConnectLib: Target = .systemLibrary(
    name: "COpenConnectLib",
    pkgConfig: "openconnect",
    providers: [.apt(["libopenconnect-dev"])]
)
#else
let cOpenConnectLib: Target = .binaryTarget(
    name: "COpenConnectLib",
    path: "Frameworks/OpenConnectC.xcframework"
)
#endif

let package = Package(
    name: "OpenConnectKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OpenConnectKit", targets: ["OpenConnectKit"])
    ],
    targets: [
        cOpenConnectLib,
        .target(
            name: "COpenConnect",
            dependencies: ["COpenConnectLib"],
            linkerSettings: [
                .linkedLibrary("xml2"),
                .linkedLibrary("z"),
                .linkedLibrary("iconv"),
            ]
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
