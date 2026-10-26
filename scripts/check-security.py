from pathlib import Path
import plistlib
import re
import subprocess

root = Path(__file__).resolve().parent.parent
expected = {'com.apple.security.app-sandbox': True}
entitlements = plistlib.loads((root / 'Resources/CaptureMark.entitlements').read_bytes())
assert entitlements == expected, f'Unexpected entitlements: {entitlements}'
app = root / 'dist/CaptureMark.app'
signed = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], capture_output=True, check=True).stdout
assert plistlib.loads(signed) == expected, 'Signed app entitlements differ'
for path in (root / 'Sources').glob('*.swift'):
    text = path.read_text()
    # Direct API patterns only; standard NSTextView text copy/cut/paste is allowed.
    forbidden = r'URLSession|NWConnection|WKWebView|NSWorkspace\.shared\.open|\bProcess\(|\bposix_spawn\b|\bsystem\(|\bsocket\(|write\(to:|FileHandle|FileManager|UserDefaults|data\(forType:'
    assert not re.search(forbidden, text), f'Forbidden API in {path.name}'
plist = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert not any(k in plist for k in ['SUFeedURL', 'CFBundleURLTypes', 'NSCameraUsageDescription', 'NSMicrophoneUsageDescription'])
clipboard = (root / 'Sources/Annotation.swift').read_text()
assert 'prepareForNewContents(with: .currentHostOnly)' in clipboard
assert not (app / 'Contents/Frameworks').exists(), 'Unexpected bundled dependency'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print('PASS: valid signature, sandbox-only entitlements, source API pattern checks, no bundled dependencies, current-host-only PNG clipboard')
