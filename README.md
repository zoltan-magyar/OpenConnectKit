# OpenConnectKit

A Swift package that wraps the [OpenConnect](https://www.infradead.org/openconnect/) C library, providing a Swift-native async/await API for VPN connections.

## Requirements

- macOS 26+
- Swift 6.4+ (Xcode 27)

## Setup

OpenConnectKit links against a static XCFramework bundling OpenConnect and OpenSSL, imported in Swift as `COpenConnect`. On `main`, `Package.swift` points at the prebuilt XCFramework attached to the latest GitHub release, so you can add the package or build it directly:

```bash
swift build
```

It's macOS only. Linux was dropped along with the C shim: OpenConnectKit needs `openconnect_set_progress_msg_handler()` (openconnect API 5.10), which no distribution ships yet.

### Building the XCFramework locally

Only needed if you're changing the C side or testing a different OpenConnect/OpenSSL version.

**1. Install the build tools:**

```bash
brew install autoconf automake libtool pkg-config
```

**2. Build the XCFramework:**

```bash
./Scripts/build-xcframework.sh
```

This clones OpenSSL and OpenConnect, builds both for arm64, and packages everything into `Frameworks/OpenConnectC.xcframework`. The first run takes a few minutes.

OpenConnect comes from the tag `swiftconnect-1` on [a fork](https://gitlab.com/zoltan-magyar/openconnect): upstream `master` plus [!664](https://gitlab.com/openconnect/openconnect/-/merge_requests/664) and [!665](https://gitlab.com/openconnect/openconnect/-/merge_requests/665), which add `openconnect_set_progress_msg_handler()`. The build switches back to upstream once a release includes it.

**3. Build the Swift package:**

```bash
swift build
```

`Package.swift` uses `Frameworks/OpenConnectC.xcframework` whenever it exists, instead of the release. Delete `Frameworks/` to go back to the release.

### Build configuration

- `Scripts/xcframework.env`: OpenSSL and OpenConnect sources and versions, shared by the build script and the release workflow.
- `Scripts/COpenConnect.modulemap`: copied into the XCFramework. It makes the headers importable as `COpenConnect` and declares the system libraries the static archive needs (`xml2`, `z`, `iconv`). Keep those in sync with the `./configure` flags in the build script.

### Rebuilding the XCFramework

To rebuild from scratch (e.g. after updating the OpenConnect source or changing the OpenSSL version):

```bash
./Scripts/build-xcframework.sh --clean
```

To build other versions without editing `xcframework.env`:

```bash
OPENSSL_VERSION=3.5.1 ./Scripts/build-xcframework.sh --clean
OPENCONNECT_VERSION=swiftconnect-2 ./Scripts/build-xcframework.sh --clean
OPENCONNECT_REPO=https://gitlab.com/openconnect/openconnect.git OPENCONNECT_VERSION=v9.22 ./Scripts/build-xcframework.sh --clean
```

## Usage

```swift
import OpenConnectKit

let handler = MyVpnHandler()  // implements VpnSessionDelegate
let session = VpnSession(delegate: handler)

let config = VpnConfiguration(
    serverURL: URL(string: "https://vpn.example.com")!,
    vpnProtocol: .anyConnect,
    logLevel: .info
)

try await session.connect(configuration: config)
```

`VpnSession` is `@Observable` — bind `session.status`, `session.stats`, and `session.interfaceName` directly in SwiftUI. Consume logs via `session.logs` (an `AsyncStream<LogEntry>`).

See `VpnSessionDelegate` for handling authentication prompts and certificate validation.
