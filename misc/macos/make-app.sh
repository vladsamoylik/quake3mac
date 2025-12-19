#!/bin/bash
# Build Quake3mac.app bundle

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    ARCH="aarch64"
fi

BUILD_DIR="${ROOT_DIR}/build/release-darwin-${ARCH}"
APP_NAME="Quake 3 Arena"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
BINARY="quake3mac.${ARCH}"

if [ ! -f "${BUILD_DIR}/${BINARY}" ]; then
    echo "Binary not found: ${BUILD_DIR}/${BINARY}"
    echo "Run 'make' first"
    exit 1
fi

echo "Creating ${APP_NAME}.app..."

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "${BUILD_DIR}/${BINARY}" "$APP_DIR/Contents/MacOS/quake3mac"

# Copy Info.plist
cp "${SCRIPT_DIR}/Info.plist" "$APP_DIR/Contents/"

# Copy icon
cp "${SCRIPT_DIR}/quake3.icns" "$APP_DIR/Contents/Resources/"

echo "Created: $APP_DIR"
echo ""
echo "To run: open \"$APP_DIR\""

