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
    url: "https://github.com/zoltan-magyar/OpenConnectKit/releases/download/v0.0.1/OpenConnectC.xcframework.zip",
    checksum: "e977fdff5dc29b7afd31e2de2a13b3351b12feec0362e9453f65419d38d1af3c"
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
            exclude: [
                "Resources/vpnc-scripts/netunshare.c",
            ],
            resources: [
                .copy("Resources/vpnc-scripts/vpnc-script")
            ],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        ),
    ]
)
