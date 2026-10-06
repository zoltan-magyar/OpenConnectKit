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

This clones OpenSSL and OpenConnect, builds both for arm64, and packages everything into `Frameworks/COpenConnect.xcframework`. The first run takes a few minutes.

OpenConnect comes from the tag `swiftconnect-2` on [a fork](https://gitlab.com/zoltan-magyar/openconnect): upstream `master` plus [!664](https://gitlab.com/openconnect/openconnect/-/merge_requests/664) and [!665](https://gitlab.com/openconnect/openconnect/-/merge_requests/665), which add `openconnect_set_progress_msg_handler()`, and [!667](https://gitlab.com/openconnect/openconnect/-/merge_requests/667), which adds `openconnect_set_reconnecting_handler()`. The build switches back to upstream once a release includes them.

**3. Build the Swift package:**

```bash
swift build
```

`Package.swift` uses `Frameworks/COpenConnect.xcframework` whenever it exists, instead of the release. Delete `Frameworks/` to go back to the release.

### Build configuration

- `Scripts/xcframework.env`: OpenSSL and OpenConnect sources and versions, shared by the build script and the release workflow.
- `Scripts/COpenConnect.modulemap`: copied into the XCFramework. It makes the headers importable as `COpenConnect` and declares the system libraries the static archive needs (`xml2`, `z`, `iconv`). Keep those in sync with the `./configure` flags in the build script.
The module map is applied on every run. After changing a version or the compiler/`./configure` flags in the script, rebuild with `--clean`: the script reuses earlier OpenSSL and openconnect builds as long as they exist.

### CI

`.github/workflows/ci.yml` lints and builds every pull request and push to `main`. It always builds the XCFramework from `Scripts/` first (cached; the cache keys include the build recipe), so changes to the C build are tested before a release ships them. `release.yml` uses the same build steps from `.github/actions/build-xcframework`.

### Rebuilding the XCFramework

To rebuild from scratch (e.g. after updating the OpenConnect source or changing the OpenSSL version):

```bash
./Scripts/build-xcframework.sh --clean
```

To build other versions without editing `xcframework.env`:

```bash
OPENSSL_VERSION=3.5.1 ./Scripts/build-xcframework.sh --clean
OPENCONNECT_VERSION=swiftconnect-1 ./Scripts/build-xcframework.sh --clean
OPENCONNECT_REPO=https://gitlab.com/openconnect/openconnect.git OPENCONNECT_VERSION=v9.22 ./Scripts/build-xcframework.sh --clean
```

## Usage

```swift
import OpenConnectKit

let prompts = VPNPrompts()  // answers auth and certificate prompts, observable for SwiftUI
let session = VPNSession(delegate: prompts)

let config = VPNConfiguration(
    serverURL: URL(string: "https://vpn.example.com")!,
    vpnProtocol: .anyConnect,
    logLevel: .info
)

try await session.connect(using: config)
```

`VPNSession` is `@Observable` — bind `session.status`, `session.lastError` and `session.stats` directly in SwiftUI. While connected, `status` is `.connected(ConnectionInfo)`, which carries the tunnel's interface name and the server; while connecting, `.connecting(ConnectionStage)` says which step is running. Consume logs via `session.logs` (an `AsyncStream<LogEntry>`; each access returns a new stream, so several readers can follow along).

`connect(using:)` returns once the tunnel is up, and throws a `VPNError` (typed throws) otherwise; the error is also kept in `lastError`, with openconnect's own explanation where it has one. Cancelling the task that called it, or calling `disconnect()`, cancels a connection attempt; `connect` then throws `VPNError.cancelled`. `disconnect()` is `async` and returns once the connection has been shut down, so switching servers is `await session.disconnect()` followed by `connect(using:)`.

Authentication forms and untrusted certificates are answered by the session's `VPNSessionDelegate`, which the session keeps alive. `VPNPrompts` is a ready-made one for SwiftUI: bind `.sheet(item: $prompts.pendingAuthentication)` and `.alert(isPresented: $prompts.isCertificatePending)`, and answer with `submit(_:)`, `acceptCertificate()` and so on. Implement the protocol yourself for anything else, such as a command-line tool. If the connection attempt is cancelled while a prompt is waiting, the prompt is withdrawn.
