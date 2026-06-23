#!/bin/bash
# Builds OpenConnectC.xcframework — a static arm64 XCFramework bundling
# openconnect + OpenSSL (libssl + libcrypto) for use by OpenConnectKit.
#
# Prerequisites (all via Homebrew):
#   brew install autoconf automake libtool pkg-config
#
# Usage:
#   ./Scripts/build-xcframework.sh          # build
#   ./Scripts/build-xcframework.sh --clean  # wipe intermediate artifacts and rebuild

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_DIR="$KIT_ROOT/.build-xcframework"
OPENSSL_SRC="$BUILD_DIR/openssl-src"
OPENSSL_OUT="$BUILD_DIR/openssl-arm64"
OC_SRC="$BUILD_DIR/openconnect-src"
OC_OUT="$BUILD_DIR/openconnect-arm64"
MERGED_OUT="$BUILD_DIR/merged"
XCFRAMEWORK_OUT="$KIT_ROOT/Frameworks/OpenConnectC.xcframework"

VPNC_SCRIPT="$KIT_ROOT/Resources/vpnc-scripts/vpnc-script"

# ── Config ────────────────────────────────────────────────────────────────────
# Override any of these via environment variables, e.g.:
#   OPENSSL_VERSION=3.5.1 ./Scripts/build-xcframework.sh

# OpenSSL release to build against. Find releases at:
# https://github.com/openssl/openssl/releases
OPENSSL_VERSION="${OPENSSL_VERSION:-3.5.0}"
OPENSSL_TAG="openssl-$OPENSSL_VERSION"
OPENSSL_REPO="https://github.com/openssl/openssl.git"

# OpenConnect release to build. Find releases at:
# https://gitlab.com/openconnect/openconnect/-/releases
OPENCONNECT_VERSION="${OPENCONNECT_VERSION:-v9.21}"
OPENCONNECT_REPO="https://gitlab.com/openconnect/openconnect.git"

DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-26.0}"
NCPU="$(sysctl -n hw.logicalcpu)"
SDK_PATH="$(xcrun --show-sdk-path)"

# ── Flags ─────────────────────────────────────────────────────────────────────

ARM64_CFLAGS="-arch arm64 -isysroot $SDK_PATH -mmacosx-version-min=$DEPLOYMENT_TARGET"

# ── Helpers ───────────────────────────────────────────────────────────────────

step() { echo; echo "▶ $*"; }

# ── Argument handling ─────────────────────────────────────────────────────────

if [[ "${1:-}" == "--clean" ]]; then
    step "Cleaning intermediate build artifacts"
    rm -rf "$BUILD_DIR"
fi

# ── Validate prerequisites ────────────────────────────────────────────────────

step "Checking prerequisites"

for tool in autoconf automake libtool pkg-config git xcodebuild xcrun; do
    if ! command -v "$tool" &>/dev/null; then
        echo "error: '$tool' not found — install with: brew install autoconf automake libtool pkg-config"
        exit 1
    fi
done

if [ ! -x "$VPNC_SCRIPT" ]; then
    echo "error: vpnc-script not found or not executable at $VPNC_SCRIPT"
    exit 1
fi

mkdir -p "$BUILD_DIR" "$OPENSSL_OUT" "$OC_OUT/lib" "$OC_OUT/include" "$MERGED_OUT/lib" "$MERGED_OUT/include"

# ── OpenSSL ───────────────────────────────────────────────────────────────────

step "Fetching OpenSSL $OPENSSL_TAG"

if [ ! -d "$OPENSSL_SRC" ]; then
    git clone --depth 1 --branch "$OPENSSL_TAG" "$OPENSSL_REPO" "$OPENSSL_SRC"
else
    echo "  (already present, skipping clone)"
fi

step "Building OpenSSL for arm64"

pushd "$OPENSSL_SRC" > /dev/null

./Configure darwin64-arm64-cc \
    no-shared \
    no-tests \
    no-apps \
    "-mmacosx-version-min=$DEPLOYMENT_TARGET" \
    "--prefix=$OPENSSL_OUT"

make -j"$NCPU"
make install_sw   # installs libs/headers, skips man pages and docs

make distclean

popd > /dev/null

# ── openconnect ───────────────────────────────────────────────────────────────

step "Fetching OpenConnect $OPENCONNECT_VERSION"

if [ ! -d "$OC_SRC" ]; then
    git clone --depth 1 --branch "$OPENCONNECT_VERSION" "$OPENCONNECT_REPO" "$OC_SRC"
else
    echo "  (already present, skipping clone)"
fi

step "Generating openconnect build system"

pushd "$OC_SRC" > /dev/null

./autogen.sh

step "Configuring openconnect for arm64"

# openconnect requires in-tree builds (out-of-tree is unreliable with its autotools setup)
./configure \
    --prefix="$OC_OUT" \
    "--with-vpnc-script=$VPNC_SCRIPT" \
    \
    `# SSL library — use OpenSSL (built above), not GnuTLS` \
    --without-gnutls \
    --with-openssl \
    \
    `# Build as static library only — no shared dylib` \
    --enable-static \
    --disable-shared \
    \
    `# Optional features — disabled to minimise binary size and system dependencies.` \
    `# Re-enable any of these if you need the corresponding VPN protocol or feature.` \
    --without-stoken    `# RSA SecurID software tokens (requires libstoken)` \
    --without-libpskc   `# OATH PSKC file support (requires libpskc >= 2.2.0)` \
    --without-libpcsclite `# Smartcard / Yubikey support (requires libpcsclite)` \
    --without-libproxy  `# Proxy auto-config PAC support (requires libproxy)` \
    --without-lz4       `# LZ4 compression for DTLS (requires liblz4)` \
    --without-gssapi    `# Kerberos/GSSAPI authentication` \
    --disable-nls       `# Native language support / gettext translations` \
    \
    CC="$(xcrun -find clang)" \
    CFLAGS="$ARM64_CFLAGS" \
    "PKG_CONFIG_PATH=$OPENSSL_OUT/lib/pkgconfig"

step "Building openconnect (library only)"

# libopenconnect.la only — skips the openconnect CLI binary and tests
make -j"$NCPU" libopenconnect.la

# libtool hides the real .a inside .libs/
cp .libs/libopenconnect.a "$OC_OUT/lib/"
cp openconnect.h "$OC_OUT/include/"

make distclean

popd > /dev/null

# ── Merge static libraries ────────────────────────────────────────────────────

step "Merging openconnect + OpenSSL into single static archive"

libtool -static \
    -o "$MERGED_OUT/lib/libopenconnect-full.a" \
    "$OC_OUT/lib/libopenconnect.a" \
    "$OPENSSL_OUT/lib/libssl.a" \
    "$OPENSSL_OUT/lib/libcrypto.a"

cp "$OC_OUT/include/openconnect.h" "$MERGED_OUT/include/"

# ── XCFramework ───────────────────────────────────────────────────────────────

step "Packaging XCFramework"

rm -rf "$XCFRAMEWORK_OUT"

xcodebuild -create-xcframework \
    -library "$MERGED_OUT/lib/libopenconnect-full.a" \
    -headers "$MERGED_OUT/include" \
    -output "$XCFRAMEWORK_OUT"

step "Done"
echo "  Output: $XCFRAMEWORK_OUT"
