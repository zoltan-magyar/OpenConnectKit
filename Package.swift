// swift-tools-version: 6.4
import Foundation
import PackageDescription

// The released XCFramework (openconnect + OpenSSL). The release workflow replaces
// both values when it publishes a new version.
let releaseURL =
  "https://github.com/zoltan-magyar/OpenConnectKit/releases/download/v0.2.1/COpenConnect.xcframework.zip"
let releaseChecksum = "2c08b4a162339cb18aabcd3fbdecbdbc4a8d03fd9deba700af0282b62393d1a0"

// A local build from Scripts/build-xcframework.sh takes precedence over the release.
// Frameworks/ is gitignored, so a checkout from Git always uses the release.
let localXCFramework = "Frameworks/COpenConnect.xcframework"
let cOpenConnect: Target =
  FileManager.default.fileExists(atPath: "\(Context.packageDirectory)/\(localXCFramework)")
  ? .binaryTarget(name: "COpenConnect", path: localXCFramework)
  : .binaryTarget(name: "COpenConnect", url: releaseURL, checksum: releaseChecksum)

let package = Package(
  name: "OpenConnectKit",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "OpenConnectKit", targets: ["OpenConnectKit"])
  ],
  targets: [
    cOpenConnect,
    .target(
      name: "OpenConnectKit",
      dependencies: ["COpenConnect"],
      // LEGACY: the vpnc-scripts submodule only exists to bundle `vpnc-script` for
      // `openconnect_setup_tun_device()`. Remove the submodule, these excludes, the resource
      // below and `Connection/VPNContext+VpncScript.swift` once TUN setup is implemented in
      // Swift (see ROADMAP.md).
      exclude: [
        "Resources/vpnc-scripts/COPYING",
        "Resources/vpnc-scripts/netunshare.c",
        "Resources/vpnc-scripts/tests",
        "Resources/vpnc-scripts/vpnc-script-ptrtd",
        "Resources/vpnc-scripts/vpnc-script-sshd",
        "Resources/vpnc-scripts/vpnc-script-win.js",
        "Resources/vpnc-scripts/xinetd.netns.conf",
      ],
      resources: [
        .copy("Resources/vpnc-scripts/vpnc-script")
      ],
      swiftSettings: [
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("MemberImportVisibility"),
      ]
    ),
  ]
)
