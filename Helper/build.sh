#!/bin/zsh
# Build and install the screen-capture helper app.
#
# TCC notes: the helper needs Screen Recording permission. This project signs it
# ad-hoc, so TCC keys the grant to the binary's cdhash — rebuilding invalidates
# the grant and macOS will ask again (or the capture will report authorized=false).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Helper/main.swift"
PLIST="$ROOT/Helper/Info.plist"
BUILD="$ROOT/Helper/ClaudeMirrorHelper.app"
DEST="$HOME/Library/Application Support/iPhoneMirror/Helper/ClaudeMirrorHelper.app"

mkdir -p "$BUILD/Contents/MacOS"
swiftc -O "$SRC" -o "$BUILD/Contents/MacOS/ClaudeMirrorHelper" \
  -framework Cocoa -framework ScreenCaptureKit -framework CoreGraphics
cp "$PLIST" "$BUILD/Contents/Info.plist"
codesign --force --deep --sign - "$BUILD"
echo "built $BUILD"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$(dirname "$DEST")"
  rm -rf "$DEST"
  cp -R "$BUILD" "$DEST"
  echo "installed $DEST"
  echo "launching helper (approve Screen Recording when macOS asks)"
  open "$DEST"
fi
