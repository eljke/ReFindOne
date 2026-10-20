#!/usr/bin/env bash
# Build a REAL iOS .app/unsigned IPA on macOS with Xcode installed.
# LiveContainer may sign a guest app as part of its supported JIT-less workflow.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo 'ERROR: Requires macOS/Xcode.' >&2; exit 1; }
command -v zip >/dev/null || { echo 'ERROR: zip is missing.' >&2; exit 1; }

xcodebuild -project ReFindOne.xcodeproj -scheme ReFindOne \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/Derived CODE_SIGNING_ALLOWED=NO build

app='build/Derived/Build/Products/Release-iphoneos/ReFindOne.app'
[[ -d "$app" ]] || { echo 'Build did not produce an .app' >&2; exit 1; }
rm -rf build/ipa
mkdir -p build/ipa/Payload
cp -R "$app" build/ipa/Payload/
rm -f build/ReFindOne-unsigned.ipa
(cd build/ipa && zip -qr ../ReFindOne-unsigned.ipa Payload)
echo "Produced: $(pwd)/build/ReFindOne-unsigned.ipa"
