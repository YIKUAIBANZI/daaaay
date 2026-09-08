#!/bin/bash
set -euo pipefail
native_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$native_dir"
swift build -c release --product Daaaay
binary_dir="$(swift build -c release --show-bin-path)"
mkdir -p build
bundle="$native_dir/build/daaaay.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_dir/Daaaay" "$bundle/Contents/MacOS/Daaaay"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
swift scripts/make-icon.swift "$native_dir/build/AppIcon.iconset"
iconutil -c icns "$native_dir/build/AppIcon.iconset" -o "$bundle/Contents/Resources/AppIcon.icns"
# Finder may attach metadata to new bundles under Desktop/iCloud.
# Clear metadata only on this generated artifact before local signing.
xattr -cr "$bundle"
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
echo "$bundle"
