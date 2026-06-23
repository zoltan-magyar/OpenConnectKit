# OpenConnectKit

A Swift package that wraps the [OpenConnect](https://www.infradead.org/openconnect/) C library, providing a Swift-native async/await API for VPN connections.

## Requirements

- macOS 26+
- Swift 6.3+
- Homebrew: `brew install autoconf automake libtool pkg-config`

## Setup

OpenConnectKit links against a static XCFramework bundling OpenConnect and OpenSSL. You must build it once before building the Swift package.

**1. Build the XCFramework:**

```bash
./Scripts/build-xcframework.sh
```

This clones OpenSSL 3.5.0 and OpenConnect v9.21, builds both for arm64, and packages everything into `Frameworks/OpenConnectC.xcframework`. Takes a few minutes on first run.

**3. Build the Swift package:**

```bash
swift build
```

### Rebuilding the XCFramework

To rebuild from scratch (e.g. after updating the OpenConnect source or changing the OpenSSL version):

```bash
./Scripts/build-xcframework.sh --clean
```

To build with different versions:

```bash
OPENSSL_VERSION=3.5.1 ./Scripts/build-xcframework.sh --clean
OPENCONNECT_VERSION=v9.22 ./Scripts/build-xcframework.sh --clean
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
