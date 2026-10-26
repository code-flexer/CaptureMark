#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build dist/CaptureMark.app/Contents/MacOS dist/CaptureMark.app/Contents/Resources
xcrun swift -module-cache-path "$PWD/.build/ModuleCache" scripts/make-icon.swift .build/CaptureMark.iconset
iconutil -c icns .build/CaptureMark.iconset -o Resources/CaptureMark.icns
xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos14.0" \
  -module-cache-path "$PWD/.build/ModuleCache" \
  Sources/*.swift -o dist/CaptureMark.app/Contents/MacOS/CaptureMark \
  -framework AppKit -framework ScreenCaptureKit -framework Carbon
cp Resources/Info.plist dist/CaptureMark.app/Contents/Info.plist
cp Resources/CaptureMark.icns dist/CaptureMark.app/Contents/Resources/CaptureMark.icns
# Default to ad-hoc signing; an installed certificate is optional.
# No timestamp service is contacted for this local development build.
signing_identity=${CAPTUREMARK_CODE_SIGN_IDENTITY:--}
codesign --force --sign "$signing_identity" --timestamp=none --options runtime --entitlements Resources/CaptureMark.entitlements dist/CaptureMark.app
codesign --verify --deep --strict dist/CaptureMark.app
printf 'Built: %s/dist/CaptureMark.app\n' "$PWD"
