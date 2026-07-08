#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/AppBundle/Info.plist")"
fi

ARCH="$(uname -m)"
ARTIFACT_DIR="$ROOT_DIR/.build/release-artifacts"
STAGING_DIR="$ARTIFACT_DIR/staging/SubSight-$VERSION"
APP_DIR="$STAGING_DIR/SubSight.app"
OUTPUT_DIR="$ARTIFACT_DIR/SubSight-$VERSION"

rm -rf "$STAGING_DIR" "$OUTPUT_DIR"
mkdir -p "$STAGING_DIR" "$OUTPUT_DIR"

cd "$ROOT_DIR"

CONFIGURATION=release APP_DIR="$APP_DIR" "$ROOT_DIR/Scripts/build-app.sh" >/dev/null
swift build -c release --product subsightctl

BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/subsightctl" "$STAGING_DIR/subsightctl"

ditto -c -k --keepParent "$APP_DIR" "$OUTPUT_DIR/SubSight-$VERSION-macos-app.zip"
tar -czf "$OUTPUT_DIR/subsightctl-$VERSION-macos-$ARCH.tar.gz" -C "$STAGING_DIR" subsightctl

(
  cd "$OUTPUT_DIR"
  shasum -a 256 ./* > SHA256SUMS.txt
)

echo "$OUTPUT_DIR"
