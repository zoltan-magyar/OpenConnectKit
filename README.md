# OpenConnectKit

A Swift-native library wrapping the [openconnect](https://www.infradead.org/openconnect/) C VPN library. Provides an `@Observable` API designed for SwiftUI applications.

## Requirements

- Swift 6.3+ / Xcode with Swift 6.3
- macOS 26+
- [openconnect](https://gitlab.com/openconnect/openconnect) source repository (cloned alongside this repo)
- [Homebrew](https://brew.sh) (for build tools only)

## Building

OpenConnectKit links against a static xcframework built from the openconnect C library and OpenSSL. This must be generated once before building.

### 1. Clone the openconnect source

The build script expects the openconnect source at `../openconnect/` relative to this repo:

```bash
git clone https://gitlab.com/openconnect/openconnect.git ../openconnect
```

### 2. Install build tools

```bash
brew install autoconf automake libtool pkg-config
```

### 3. Build the xcframework

```bash
./Scripts/build-xcframework.sh
```

This builds OpenSSL and openconnect from source as static libraries and packages them into `Frameworks/OpenConnectC.xcframework`. The first run takes a few minutes; subsequent runs use cached artifacts.

### 4. Build OpenConnectKit

```bash
swift build
```

Or add it as a local package dependency in Xcode.

## Usage

```swift
import OpenConnectKit

let handler = MyVpnHandler()
let session = VpnSession(delegate: handler)

let config = VpnConfiguration(
    serverURL: URL(string: "https://vpn.example.com")!,
    vpnProtocol: .anyConnect
)

try await session.connect(configuration: config)
```

`VpnSession` is `@Observable` — bind `session.status`, `session.stats`, and `session.interfaceName` directly in SwiftUI views.

## System libraries

The following system libraries are linked automatically (provided by macOS):

- `libxml2`
- `zlib`
- `libiconv`

No Homebrew libraries are required at runtime.
