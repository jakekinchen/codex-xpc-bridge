# Locked Facts: Codex XPC Bridge Baseline

Date: 2026-03-12
Owner: Worker C
Status: Active

## Purpose

This file is the factual baseline for the cold-start bridge package in this repository. It separates:

1. facts confirmed locally in `/Users/jakekinchen/Documents/codex-xpc-bridge`
2. facts asserted by `prompt-seed.txt` but not verifiable because the referenced upstream app repo is unavailable
3. architectural conclusions that are design decisions, not yet implementation evidence

## Confirmed local facts

- The current repository contains `prompt-seed.txt` and no implementation files from the referenced upstream app codebase.
- The repository path named in the seed prompt, `/path/to/host-app-macos`, does not exist on this machine.
- The specific files named as authoritative repo docs in the seed prompt cannot be read locally because the target repo is absent:
  - `docs/app-store/mas-codex-runtime-checklist.md`
  - `docs/plans/active/2026-03-09-mas-agent-service-parity-plan.md`
  - `docs/plans/active/2026-03-09-mas-codex-app-server-protocol-prd.md`
  - `docs/plans/active/2026-03-09-swift-codex-control-plane-plan.md`
- This repository therefore began as a cold-start implementation package derived from the seed prompt plus Apple primary-source constraints, not a code-audited update to an upstream app repo.

## Seed-prompt assertions requiring later validation

The following were treated as requirements or prior-state assertions from `prompt-seed.txt`. They are not locally verified in this repository and should be treated as historical context, not package requirements.

- MAS currently stubs out the internal helper runtime in `Sources/HostAppMacOSApp/HostAppInternalHelperRuntime.swift`.
- MAS packaging currently strips daemon/tool/script payloads in `scripts/release/testflight-readiness.sh`.
- The external runtime assumes bundled Node, `127.0.0.1`, and child-process helper launch in `Sources/HostAppMacOSAppInternal/HostAppBundledInternalHelperRuntime.swift`.
- The current Codex client assumes `codex app-server --listen stdio://` in `daemon/src/codex-app-server-client.ts`.
- Container-scoped runtime workspace persistence already exists in:
  - `Sources/HostAppMacOSApp/HostAppContainer.swift`
  - `Sources/HostAppMacOSApp/HostAppRuntimeWorkspaceService.swift`
  - `daemon/src/runtime-workspace.ts`
- Workspace file persistence already exists through `write_workspace_file` in `daemon/src/agent-tool-executor.ts`.
- Saved user visuals already externalize WGSL into user-library files in `daemon/src/library-service.ts`.
- Shader conversion currently shells out to `scripts/wgsl/convert-any-shader.mjs`.
- Validation can be internalized because `scripts/wgsl/convert-any-shader.mjs` already contains inline apply, probe, and frame validation logic.

## Primary-source constraints treated as authoritative

These constraints come from Apple documentation and govern the design in this repo packet.

- App Review Guideline 2.4.5(iii) requires Mac App Store apps to be appropriately sandboxed.
- App Review Guideline 2.5.2 disallows apps downloading, installing, or executing code that introduces or changes app features after review.
- App Sandbox guidance explicitly supports bundling helper tools and using XPC services inside sandboxed macOS apps.
- Apple’s entitlement reference states that child processes inherit the parent app’s sandbox when `com.apple.security.inherit` is used.
- Apple’s XPC service guidance describes XPC services as bundled helper executables that launch on demand and can be restarted independently of the host app.

Primary sources:

- <https://developer.apple.com/app-store/review/guidelines/>
- <https://developer.apple.com/documentation/security/app-sandbox>
- <https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox/>
- <https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html>
- <https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html>

## Locked architecture decisions for this package

These are deliberate project decisions carried forward unless contradicted by new evidence.

- The MAS runtime path uses `app shell -> private bundled XPC service -> bundled native Codex binary over stdio`.
- The MAS runtime path does not use Node, localhost HTTP, localhost WebSocket transport, or post-review helper downloads.
- The XPC service owns Codex process lifecycle and mediates all app-facing runtime traffic.
- `CODEX_HOME` and all mutable assistant state live in the app container, not inside the app bundle.
- Tooling is closed over a typed allowlist and is limited to container-scoped or user-granted files.
- The default demo surface is WGSL-first and shader-assistant-first; real hosts are expected to inject their own bounded tool surface.
- Approval flows remain visible in the app shell, but approval decisions are enforced by the XPC service before tool execution.

## Evidence gaps that must be closed in a real implementation repo

- Whether the native Codex binary can authenticate for the intended provider modes without localhost callback behavior.
- Whether all required provider modes are MAS-safe, or whether MAS v1 must ship with a reduced provider set.
- Whether the current app-server protocol can be reused directly over stdio or should be re-expressed as a slimmer app-specific envelope.
- Whether shader conversion should continue to rely on bundled binaries or be partially reimplemented in Swift for MAS v1.
- Exact bundle structure, entitlements, and signing chain for the app shell, the XPC service, and the bundled Codex binary.
- Existing UI and persistence seams that can be reused versus rewritten.

## Immediate package consequence

No implementation claim in this repository should be read as “already verified in some upstream host app.” The package and docs here should be treated as a reusable reference bridge plus historical notes from the original seed prompt.
