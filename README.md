# CodexXPCBridge

[![SwiftPM](https://github.com/jakekinchen/codex-xpc-bridge/actions/workflows/swiftpm.yml/badge.svg)](https://github.com/jakekinchen/codex-xpc-bridge/actions/workflows/swiftpm.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

`CodexXPCBridge` is a SwiftPM macOS reference project for a Mac App Store-safe Codex runtime topology:

- a SwiftUI app shell
- a private bundled XPC service
- a bundled native `codex` runtime over newline-delimited JSON on stdio

Nothing in the code or packaging layer is product-specific. The defaults are meant to be reusable for Codex-backed macOS apps that need a narrow, inspectable boundary between user-facing UI, privileged local automation, and a bundled agent runtime.

## Why this exists

Codex-style desktop apps often need to launch a local runtime, broker tool calls, surface approval prompts, and confine file operations. On macOS, especially for App Store-oriented apps, that topology needs to be explicit:

- the app owns UX, transcript state, approvals, and artifact display
- the XPC service owns process supervision and the trust boundary
- the runtime speaks a small stdio protocol instead of reaching directly into app state
- host apps inject their own tool executor, approval policy, and artifact behavior

This repo packages that shape as a small reference implementation with tests rather than a product-specific code dump.

## Current status

- SwiftPM package with reusable contract, support, XPC, relay, service-core, and demo-app targets.
- Deterministic fixture `codex` runtime for local testing.
- Demo SwiftUI shell with transcript, approvals, and artifact surfacing.
- Packaging scripts for a debug app bundle containing the app, XPC service, and runtime.
- Test coverage for protocol round trips, path confinement, bounded tool execution, broker integration, approvals, timeouts, restarts, relay config, artifacts, and malformed runtime output.

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
- `Sources/CodexBridgeRelaySupport/`: relay configuration helpers for resolving service identifiers
- `Sources/CodexBridgeRelay/`: relay executable for bridge clients that need a command-line entry point
- `Sources/CodexBridgeSupport/`: path resolution, diagnostics, tool execution, and session reduction
- `Sources/CodexBridgeXPC/`: NSXPC protocols and envelope codec helpers
- `Sources/CodexBridgeServiceCore/`: process supervision and session brokering for the service
- `Sources/CodexBridgeService/`: `NSXPCListener.service()` entry point
- `Sources/CodexBridgeApp/`: SwiftUI macOS shell with transcript, approvals, and artifact surfacing
- `Sources/codex/`: deterministic demo runtime that speaks the same protocol over stdio

The bundled `codex` target and the default `DemoToolExecutor` are fixture/demo implementations. Real apps are expected to keep the transport/process layers and inject their own tool handler, approval policy, and host artifact behavior into `CodexSessionBroker`.

## Quick start

Requirements:

- macOS 14 or newer
- Swift 6.1 or newer

Run the tests:

```bash
swift test
```

Build all package products:

```bash
swift build
```

Package and launch the demo app:

```bash
scripts/package_app.sh debug
scripts/launch.sh
```

Or compile, package, and launch in one step:

```bash
scripts/compile_and_run.sh
```

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
- policy and edge-case tests for approval timeouts, startup timeouts, runtime crashes, malformed stdout, restart budgets, and host policy overrides

## Expected usage

1. Run `swift test`.
2. Run `scripts/package_app.sh debug`.
3. Launch with `scripts/compile_and_run.sh` or `scripts/launch.sh`.
4. Use the quick actions in the app shell to drive the bounded tool flows and approval UX.

## Adapting the bridge

For a real host app, start by replacing three seams:

1. Runtime binary: bundle your real `codex` runtime instead of the deterministic fixture target under `Sources/codex/`.
2. Tool execution: provide a host-specific implementation for bounded tool calls instead of the demo executor in `CodexBridgeSupport`.
3. Approval policy: configure the service with the tools that can run automatically and the tools that must always surface approval to the user.

Keep the contract small. Runtime messages should stay explicit enough to test with fixtures and review in logs.

## Security posture

This project is a reference implementation, not a blanket permission model. The default posture is intentionally narrow:

- path resolution rejects absolute paths and traversal outside the workspace root
- unknown tools require approval by default
- approval waits and runtime startup have explicit timeouts
- malformed runtime stdout is treated as a protocol violation
- runtime crashes and cancellations are surfaced as structured events

See [SECURITY.md](SECURITY.md) for reporting guidance and [docs/app-store/](docs/app-store/) for the App Store review and bounded-tool notes.

## Contributing

Issues and pull requests are welcome, especially around:

- real Codex runtime integration notes
- App Store packaging and signing edge cases
- protocol compatibility tests
- stricter sandbox and approval examples
- clearer docs for host apps adopting the bridge

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
