# Contributing

Thanks for helping improve `CodexXPCBridge`. The project is intended to stay small, reusable, and reviewable for macOS apps that need a Codex runtime boundary.

## Good first contributions

- tighten or expand SwiftPM tests around bridge protocol behavior
- document App Store packaging, signing, and XPC edge cases
- add host-app adaptation examples
- improve approval-policy and sandboxing examples
- report real-world runtime integration issues with enough logs to reproduce

## Development setup

Requirements:

- macOS 14 or newer
- Swift 6.1 or newer

Run the full local check before opening a pull request:

```bash
swift test
```

To inspect the demo bundle:

```bash
scripts/package_app.sh debug
scripts/launch.sh
```

## Pull request expectations

- Keep the bridge protocol narrow and testable.
- Add or update tests for behavior changes.
- Keep product-specific policy out of the reusable layers.
- Document new host-app assumptions in `README.md` or `docs/`.
- Avoid committing built app bundles, DerivedData, or local signing artifacts.

## Design boundaries

The demo `codex` target is a fixture runtime. Real host apps should replace the runtime and tool executor while preserving the app/XPC/service boundary. If a change makes the app shell, XPC service, or runtime less separable, call that out explicitly in the pull request.
