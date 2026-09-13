#!/usr/bin/env bash
set -euo pipefail

IOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$IOS_ROOT/Core/core.lock.json"
CACHE="$IOS_ROOT/Vendor/.cache"
OUTPUT="$IOS_ROOT/Vendor/MihomoCore.xcframework"

lock_value() {
    /usr/bin/python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$LOCK" "$1"
}

download() {
    local url="$1" destination="$2" checksum="$3"
    if [[ ! -f "$destination" ]]; then
        curl --fail --location --retry 3 --output "$destination.download" "$url"
        mv "$destination.download" "$destination"
    fi
    printf '%s  %s\n' "$checksum" "$destination" | shasum -a 256 --check
}

REVISION="$(lock_value revision)"
SOURCE="$CACHE/mihomo-$REVISION"
BUILD="$CACHE/build-$REVISION"
mkdir -p "$CACHE"

download "$(lock_value archive_url)" "$CACHE/$REVISION.tar.gz" "$(lock_value archive_sha256)"
if [[ ! -d "$SOURCE" ]]; then
    mkdir -p "$SOURCE.extracting"
    tar -xzf "$CACHE/$REVISION.tar.gz" --strip-components=1 -C "$SOURCE.extracting"
    mv "$SOURCE.extracting" "$SOURCE"
fi

if [[ -n "${GO:-}" ]]; then
    GO_BIN="$GO"
elif command -v go >/dev/null 2>&1; then
    GO_BIN="$(command -v go)"
elif [[ "$(uname -s)/$(uname -m)" == "Darwin/arm64" ]]; then
    GO_VERSION="$(lock_value go_version)"
    GO_DIRECTORY="$CACHE/go-$GO_VERSION"
    download "$(lock_value go_darwin_arm64_url)" "$CACHE/go-$GO_VERSION.tar.gz" "$(lock_value go_darwin_arm64_sha256)"
    if [[ ! -x "$GO_DIRECTORY/go/bin/go" ]]; then
        mkdir -p "$GO_DIRECTORY"
        tar -xzf "$CACHE/go-$GO_VERSION.tar.gz" -C "$GO_DIRECTORY"
    fi
    GO_BIN="$GO_DIRECTORY/go/bin/go"
else
    printf 'Install Go %s and set GO=/absolute/path/to/go.\n' "$(lock_value go_version)" >&2
    exit 1
fi

"$GO_BIN" version
export GOTOOLCHAIN=local
export GOCACHE="$CACHE/go-build"
export GOMODCACHE="$CACHE/go-mod"
export GOPATH="$CACHE/go-path"
IOS_MINIMUM="$(lock_value ios_minimum)"

build_slice() {
    local name="$1" sdk="$2" target="$3" minimum_flag="$4"
    local sdk_root compiler
    sdk_root="$(xcrun --sdk "$sdk" --show-sdk-path)"
    compiler="$(xcrun --sdk "$sdk" --find clang)"
    mkdir -p "$BUILD/$name"
    (
        cd "$SOURCE"
        GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC="$compiler" \
            CGO_CFLAGS="-isysroot $sdk_root $minimum_flag -target $target" \
            CGO_LDFLAGS="-isysroot $sdk_root $minimum_flag -target $target" \
            "$GO_BIN" build -mod=readonly -trimpath -tags with_gvisor -buildmode=c-archive \
            -o "$BUILD/$name/libswihomo_core.a" ./bridge
    )
}

build_slice ios-arm64 iphoneos "arm64-apple-ios$IOS_MINIMUM" "-miphoneos-version-min=$IOS_MINIMUM"
build_slice ios-arm64-simulator iphonesimulator "arm64-apple-ios$IOS_MINIMUM-simulator" "-mios-simulator-version-min=$IOS_MINIMUM"

mkdir -p "$BUILD/headers"
cp "$IOS_ROOT/Core/SwihomoCore.h" "$BUILD/headers/SwihomoCore.h"
STAGING="$(mktemp -d "$CACHE/xcframework.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
xcodebuild -create-xcframework \
    -library "$BUILD/ios-arm64/libswihomo_core.a" -headers "$BUILD/headers" \
    -library "$BUILD/ios-arm64-simulator/libswihomo_core.a" -headers "$BUILD/headers" \
    -output "$STAGING/MihomoCore.xcframework"
cp "$LOCK" "$STAGING/MihomoCore.xcframework/core.lock.json"
rm -rf "$OUTPUT"
mv "$STAGING/MihomoCore.xcframework" "$OUTPUT"
printf 'Built %s\n' "$OUTPUT"
