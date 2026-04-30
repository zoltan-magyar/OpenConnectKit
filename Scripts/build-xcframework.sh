#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OPENCONNECT_SRC="$(dirname "$PROJECT_DIR")/openconnect"
VPNC_SCRIPT="$PROJECT_DIR/Resources/vpnc-scripts/vpnc-script"
BUILD_DIR="$PROJECT_DIR/.build-xcframework"
FRAMEWORK_DIR="$PROJECT_DIR/Frameworks"
NCPU="$(sysctl -n hw.ncpu)"

OPENSSL_VERSION="openssl-3.5.0"

echo "=== OpenConnectKit XCFramework Builder ==="
echo "Build dir: $BUILD_DIR"
echo "OpenConnect source: $OPENCONNECT_SRC"
echo ""

if [ ! -d "$OPENCONNECT_SRC" ]; then
  echo "ERROR: openconnect source not found at $OPENCONNECT_SRC"
  echo "Clone it: git clone https://gitlab.com/openconnect/openconnect.git $OPENCONNECT_SRC"
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Clone/update OpenSSL
# ---------------------------------------------------------------------------
OPENSSL_SRC="$BUILD_DIR/openssl-src"
if [ ! -d "$OPENSSL_SRC" ]; then
  echo "=== Cloning OpenSSL ($OPENSSL_VERSION) ==="
  git clone --depth 1 --branch "$OPENSSL_VERSION" \
    https://github.com/openssl/openssl.git "$OPENSSL_SRC"
else
  echo "=== OpenSSL source already present, skipping clone ==="
fi

# ---------------------------------------------------------------------------
# Step 2: Build OpenSSL (arm64)
# ---------------------------------------------------------------------------
OPENSSL_PREFIX="$BUILD_DIR/openssl-arm64"

if [ -f "$OPENSSL_PREFIX/lib/libssl.a" ]; then
  echo "=== OpenSSL already built, skipping ==="
else
  echo "=== Building OpenSSL (arm64) ==="
  cd "$OPENSSL_SRC"
  make clean 2>/dev/null || true

  ./Configure darwin64-arm64-cc \
    no-shared \
    no-tests \
    no-ui-console \
    no-apps \
    --prefix="$OPENSSL_PREFIX"

  make -j"$NCPU"
  make install_sw
  cd "$PROJECT_DIR"
fi

# ---------------------------------------------------------------------------
# Step 3: Build openconnect (arm64)
#
# Following the official build instructions:
# https://www.infradead.org/openconnect/building.html
# ---------------------------------------------------------------------------
OC_PREFIX="$BUILD_DIR/openconnect-arm64"

if [ -f "$OC_PREFIX/lib/libopenconnect.a" ] && [ "$(wc -c < "$OC_PREFIX/lib/libopenconnect.a")" -gt 1000 ]; then
  echo "=== openconnect already built, skipping ==="
else
  echo "=== Building openconnect (arm64) ==="
  cd "$OPENCONNECT_SRC"
  make clean 2>/dev/null || true
  make distclean 2>/dev/null || true

  ./autogen.sh

  ./configure \
    --with-vpnc-script="$VPNC_SCRIPT" \
    --without-gnutls \
    --with-openssl \
    --enable-static \
    --disable-shared \
    --without-stoken \
    --without-libpskc \
    --without-libpcsclite \
    --without-libproxy \
    --without-lz4 \
    --without-gssapi \
    --disable-nls \
    PKG_CONFIG_PATH="$OPENSSL_PREFIX/lib/pkgconfig"

  make -j"$NCPU" libopenconnect.la

  # Copy library and header
  mkdir -p "$OC_PREFIX/lib" "$OC_PREFIX/include"
  cp .libs/libopenconnect.a "$OC_PREFIX/lib/"
  cp openconnect.h "$OC_PREFIX/include/"

  local_count="$(ar t "$OC_PREFIX/lib/libopenconnect.a" | wc -l)"
  echo "  libopenconnect.a: $(wc -c < "$OC_PREFIX/lib/libopenconnect.a") bytes ($local_count object files)"

  cd "$PROJECT_DIR"
fi

# ---------------------------------------------------------------------------
# Step 4: Merge static libraries
# ---------------------------------------------------------------------------
echo "=== Merging static libraries ==="
MERGED_DIR="$BUILD_DIR/merged"
mkdir -p "$MERGED_DIR/lib" "$MERGED_DIR/include"

libtool -static -o "$MERGED_DIR/lib/libopenconnect-full.a" \
  "$OC_PREFIX/lib/libopenconnect.a" \
  "$OPENSSL_PREFIX/lib/libssl.a" \
  "$OPENSSL_PREFIX/lib/libcrypto.a"

cp "$OC_PREFIX/include/openconnect.h" "$MERGED_DIR/include/"

# ---------------------------------------------------------------------------
# Step 5: Package as XCFramework
# ---------------------------------------------------------------------------
echo "=== Creating XCFramework ==="
rm -rf "$FRAMEWORK_DIR/OpenConnectC.xcframework"
mkdir -p "$FRAMEWORK_DIR"

xcodebuild -create-xcframework \
  -library "$MERGED_DIR/lib/libopenconnect-full.a" \
  -headers "$MERGED_DIR/include" \
  -output "$FRAMEWORK_DIR/OpenConnectC.xcframework"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "=== Build complete ==="
echo "XCFramework: $FRAMEWORK_DIR/OpenConnectC.xcframework"
echo ""
lipo -info "$MERGED_DIR/lib/libopenconnect-full.a"
echo ""
echo "To clean build artifacts: rm -rf $BUILD_DIR"
