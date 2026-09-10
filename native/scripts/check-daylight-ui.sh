#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
swift build --package-path native --product DayCoreChecks
bin="$(swift build --package-path native --show-bin-path)"
sources=()
for source in native/Sources/Daaaay/*.swift; do
    case "$source" in */App.swift|*/HotKeys.swift) continue;; esac
    sources+=("$source")
done
bundle="native/build/DaylightAcceptance.app"
mkdir -p "$bundle/Contents/MacOS"
xcrun swiftc -parse-as-library -I "$bin/Modules" "${sources[@]}" \
    native/Tests/DaylightUI/Acceptance.swift "$bin"/DayCore.build/*.swift.o \
    -o "$bundle/Contents/MacOS/DaylightAcceptance"
cp native/Tests/DaylightUI/Info.plist "$bundle/Contents/Info.plist"
DAAAAY_SERVICE_URL=http://127.0.0.1:18769 "$bundle/Contents/MacOS/DaylightAcceptance" "$@"
