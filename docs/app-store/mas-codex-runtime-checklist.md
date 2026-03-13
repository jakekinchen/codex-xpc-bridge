# MAS Codex Runtime Checklist

Last updated: 2026-03-12
Status: Draft for implementation and release gating
Owner: Runtime / macOS platform

## Purpose

This checklist defines the non-negotiable conditions for shipping a Mac App Store-safe assistant runtime path built as:

- app shell
- bundled private XPC service
- bundled native Codex binary launched over stdio

The checklist is intended to replace the missing upstream artifact referenced by `prompt-seed.txt` and provide a review-safe, testable gate for implementation, QA, release, and App Review preparation.

## Primary-source policy basis

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Sandbox overview](https://developer.apple.com/documentation/security/app-sandbox)
- [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox/)
- [Enabling App Sandbox](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)
- [Creating XPC Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)

## Release-blocking architecture checks

- [ ] MAS runtime path uses a private bundled XPC service as the only app-to-runtime seam.
- [ ] XPC service launches and owns a bundled native Codex binary over stdio.
- [ ] MAS build does not depend on Node, `daemon/dist`, `daemon/node_modules`, localhost HTTP, localhost WebSocket, or a detached helper topology.
- [ ] MAS build does not require `com.apple.security.network.server` unless a later decision record proves necessity and App Review justification.
- [ ] `CODEX_HOME` resolves to an app-container path and is never mapped to the app bundle or a user-provided executable location.
- [ ] XPC service and child process lifetime rules are documented, deterministic, and test-covered.
- [ ] Tool execution is app-owned, typed, and closed over an explicit allowlist.
- [ ] Runtime writes are confined to the container workspace, library storage, or actively granted user-selected locations.

## Entitlements and sandbox checks

- [ ] App sandbox is enabled for the MAS target.
- [ ] XPC service uses the minimum entitlements required for the bounded assistant surface.
- [ ] No entitlement enables unrestricted file-system traversal, arbitrary process launch, or unexpected network serving behavior.
- [ ] Child-process behavior is treated as sandbox-inherited unless proven otherwise in code signing and runtime validation.
- [ ] If post-selection file access persists across launches, security-scoped bookmark behavior is documented and tested.

## Process and packaging checks

- [ ] Bundled Codex binary is present inside the signed app payload.
- [ ] Private XPC service is present, signed, and nested correctly.
- [ ] Bundle does not contain deprecated MAS-excluded runtime payloads.
- [ ] Bundle does not download helper executables, runtimes, or toolchains after review.
- [ ] No runtime feature path depends on executing user-provided binaries.
- [ ] No runtime feature path depends on `127.0.0.1` transport.

## Tool-surface checks

Allowed v1 tool surface:

- [ ] `import_shader`
- [ ] `convert_shader`
- [ ] `validate_shader`
- [ ] `capture_preview`
- [ ] `save_style_profile`
- [ ] `save_to_library`
- [ ] `read_workspace_file`
- [ ] `write_workspace_file`

Disallowed MAS behavior:

- [ ] Generic shell execution
- [ ] Arbitrary binary execution
- [ ] Dynamic tool discovery
- [ ] Arbitrary file traversal outside container or granted scope
- [ ] Unrestricted network access
- [ ] Open-ended code download or plugin installation

## User-visible parity checks

- [ ] Transcript streaming remains available.
- [ ] Tool calls and tool results are visible in the UI.
- [ ] Approval-required flows remain explicit and auditable.
- [ ] Draft preview generation remains available for the bounded surface.
- [ ] Save/apply completion remains available.
- [ ] Provider status remains legible.
- [ ] Workspace persistence remains intact across relaunch.
- [ ] User style memory loading and saving remain intact.
- [ ] Shader conversion, validation, preview capture, and library save remain intact for the supported WGSL-first surface.
- [ ] Error states, child-process crash states, and reconnect/retry states remain visible and actionable.

## Test and evidence checks

- [ ] Unit coverage exists for process manager, allowlist enforcement, workspace confinement, timeout handling, and event translation.
- [ ] Integration coverage exists with a fake Codex stdio fixture.
- [ ] End-to-end coverage exists for app shell -> XPC -> Codex -> app round-trips.
- [ ] Packaging checks verify bundle contents, signing, and absence of prohibited payloads.
- [ ] Security checks verify no writes outside allowed scope and no symlink escapes.
- [ ] Release artifacts include logs, parity scorecard, and smoke-suite results.

## App Review readiness checks

- [ ] Reviewer notes explain that the assistant uses a private in-bundle service and a bundled native binary for bounded document-processing tasks.
- [ ] Reviewer notes explain that tools are allowlisted and not open-ended.
- [ ] Reviewer notes do not claim capabilities the shipped build cannot demonstrate.
- [ ] Reviewer notes disclose any provider or auth limitations that remain in MAS v1.
- [ ] A human-readable explanation exists for why localhost and generic shell execution are absent from MAS.

## Forced-stop conditions

Do not ship the MAS runtime if any of the following remain true:

- The runtime still requires Node or localhost transport.
- Tool execution remains open-ended or shell-backed.
- `CODEX_HOME` or generated artifacts resolve outside the container without explicit user grants.
- Auth or provider behavior required for the supported surface is still unvalidated.
- Crash recovery, approval flow recovery, or bounded-tool parity is untested.
- App Review notes rely on vague statements instead of the actual bounded model.
