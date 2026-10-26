# CaptureMark

Read README.md before changes. Native macOS AppKit application, Swift, no package dependencies.

Publication readiness lives in RELEASE_PLAN.md. Keep one source checkout here when visibility changes. Private operational validation and build backups belong outside this repository in Workspace/project-notes/capturemark.

- Keep the product to screen region selection, annotations and explicit clipboard export.
- App Sandbox is mandatory. Never add network, camera, microphone, accessibility, automation or file access entitlements.
- No network APIs, web views, external program execution, upload, updater, analytics, image history, automatic disk writes or automatic clipboard reads in production code. Standard user-initiated text copy/cut/paste is allowed only while editing an annotation.
- Captures and annotations stay in memory until cancellation/export. Image export must contain only flattened PNG, with local-only pasteboard markers. Standard text copy/cut/paste does not use these PNG protections; keep privacy wording explicit about that distinction.
- Do not print captured images or text into logs. Do not commit build outputs.
- Build with ./scripts/build.sh; run ./scripts/test.sh for rendering/security checks.
