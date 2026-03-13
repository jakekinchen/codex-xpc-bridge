# CodexXPCBridge

`CodexXPCBridge` is a generic SwiftPM macOS reference project for a MAS-safe Codex runtime topology:

- app shell
- private bundled XPC service
- bundled native `codex` binary over stdio

Nothing in the code or packaging layer is product-specific. The defaults are reusable for any Codex-backed Mac App Store project.

## Targets and default bundle names

- app executable: `CodexXPCBridgeDemo`
- bundled XPC service: `CodexXPCBridgeService`
- bundled native runtime binary: `codex`

The packaged app shape is:

```text
CodexXPCBridgeDemo.app/
  Contents/MacOS/CodexXPCBridgeDemo
  Contents/XPCServices/CodexXPCBridgeService.xpc/
    Contents/MacOS/CodexXPCBridgeService
    Contents/Resources/codex
```

## Source layout

- `Sources/CodexBridgeContract/`: shared newline-delimited JSON envelopes and payloads
- `Sources/CodexBridgeSupport/`: path resolution, diagnostics, tool execution, and session reduction
- `Sources/CodexBridgeXPC/`: NSXPC protocols and envelope codec helpers
- `Sources/CodexBridgeServiceCore/`: process supervision and session brokering for the service
- `Sources/CodexBridgeService/`: `NSXPCListener.service()` entry point
- `Sources/CodexBridgeApp/`: SwiftUI macOS shell with transcript, approvals, and artifact surfacing
- `Sources/codex/`: deterministic demo runtime that speaks the same protocol over stdio

## Scripts

- `scripts/package_app.sh`: builds the app, the XPC service, and `codex`, then assembles `CodexXPCBridgeDemo.app`
- `scripts/compile_and_run.sh`: packages a debug build and launches it
- `scripts/launch.sh`: launches an already packaged app bundle
- `scripts/release/testflight-readiness.sh`: release gate from the planning packet

The packaging script uses neutral config templates under `Config/`:

- `CodexXPCBridgeDemo.entitlements`
- `CodexXPCBridgeService.entitlements`
- `CodexXPCBridgeDemo-Info.plist.template`
- `CodexXPCBridgeService-Info.plist.template`

## Test coverage

- protocol round-trip and payload encoding tests
- real path confinement tests
- real bounded tool execution tests for import, write, read, convert, validate, preview, style save, and library save
- subprocess integration tests that drive the session broker against a fixture runtime over stdio and verify approvals, tool execution, artifacts, and completion

## Expected usage

1. Run `swift test`.
2. Run `scripts/package_app.sh debug`.
3. Launch with `scripts/compile_and_run.sh` or `scripts/launch.sh`.
4. Use the quick actions in the app shell to drive the bounded tool flows and approval UX.
