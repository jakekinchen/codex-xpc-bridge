# MAS Release Readiness Checklist

Last updated: 2026-03-12
Status: Pre-implementation draft
Owner: Release engineering / runtime PM

## Objective

Provide the release-time checklist for the bounded MAS assistant runtime. This checklist assumes the runtime architecture is XPC + bundled native Codex over stdio and that unsupported legacy topology has been removed from the MAS path.

## Build and packaging

- [ ] App bundle contains the private XPC service in the expected nested location.
- [ ] App bundle contains the bundled native Codex binary in the expected signed location.
- [ ] Bundle does not contain Node, `daemon/dist`, `daemon/node_modules`, localhost runtime shims, or deprecated helper payloads.
- [ ] All nested code is signed consistently with the shipping identity.
- [ ] Release script asserts both required-presence and forbidden-absence checks.

## Runtime safety

- [ ] App sandbox entitlement set has been reviewed for minimum scope.
- [ ] No `network.server` entitlement is present unless backed by an approved decision record.
- [ ] Tool registry for MAS is closed and matches the documented allowlist.
- [ ] No shell-backed or arbitrary-exec tool path remains reachable in the MAS build.
- [ ] Workspace and library writes are container-scoped or user-granted.
- [ ] Security-scoped bookmark handling has been validated if post-selection access persists.

## Behavior parity

- [ ] Transcript streaming smoke test passes.
- [ ] Tool-call visibility smoke test passes.
- [ ] Tool-result visibility smoke test passes.
- [ ] Approval approve/reject smoke test passes.
- [ ] Draft preview generation smoke test passes.
- [ ] Save/apply completion smoke test passes.
- [ ] Workspace persistence across relaunch smoke test passes.
- [ ] Style memory read/write smoke test passes.
- [ ] Shader conversion, validation, preview capture, and library save smoke test passes.
- [ ] Crash/reconnect behavior smoke test passes.

## Test evidence required at release

- [ ] Unit test summary attached.
- [ ] Integration test summary attached.
- [ ] End-to-end smoke-suite summary attached.
- [ ] Packaging/signing evidence attached.
- [ ] Security regression summary attached.
- [ ] Parity scorecard attached with all `must-match` rows green or waived.
- [ ] Logs and traces are redacted for sensitive content.

## Product and documentation

- [ ] Provider/auth limitations are reflected in product copy if any remain.
- [ ] App Review notes describe the bounded tool surface honestly.
- [ ] Support and QA docs reflect MAS-specific limitations and recovery flows.
- [ ] Launch decision acknowledges any approved `acceptable-divergence` items.

## Ship blockers

Do not submit if any answer is yes:

- [ ] Does the MAS path still require localhost transport?
- [ ] Does any shipped feature require generic shell or arbitrary exec?
- [ ] Does any tool write outside the container or granted scope?
- [ ] Does any supported provider mode still lack MAS-safe auth validation?
- [ ] Does the bundle still include forbidden legacy runtime payloads?
- [ ] Does the app claim parity for behavior that is unsupported in MAS?
