#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  -module-cache-path "$PWD/.build/ModuleCache" Sources/Annotation.swift Tests/RenderTests.swift \
  -o .build/RenderTests -framework AppKit
.build/RenderTests
mkdir -p .build/SandboxProbe.app/Contents/MacOS
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/.build/ModuleCache" \
  Tests/SandboxProbe.swift -o .build/SandboxProbe.app/Contents/MacOS/SandboxProbe
python3 - <<'PY'
import plistlib
from pathlib import Path
Path('.build/SandboxProbe.app/Contents/Info.plist').write_bytes(plistlib.dumps({
 'CFBundleIdentifier': 'local.capturemark.sandbox-probe', 'CFBundleExecutable': 'SandboxProbe',
 'CFBundlePackageType': 'APPL', 'LSUIElement': True
}))
PY
codesign --force --sign - --options runtime --entitlements Resources/CaptureMark.entitlements .build/SandboxProbe.app
.build/SandboxProbe.app/Contents/MacOS/SandboxProbe
python3 scripts/check-security.py
