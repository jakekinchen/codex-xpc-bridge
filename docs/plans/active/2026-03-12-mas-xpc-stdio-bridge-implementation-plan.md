# 2026-03-12 MAS XPC Stdio Bridge Implementation Plan

Status: Active
Owner: Technical PM
Audience: App team, runtime platform, release engineering, security review

## Goal

Ship a Mac App Store-safe runtime path for the bounded assistant surface using:

`app shell -> private bundled XPC service -> bundled native Codex binary over stdio`

This plan converts the seed prompt into an implementation-ready execution packet for a missing target repo. It is intentionally explicit about what is confirmed, what is inferred, and what remains blocked by missing implementation evidence.

## Phase 1: Establish facts

## Current architecture summary

Confirmed locally:

- only `prompt-seed.txt` exists in this repo
- the host app repo referenced by the seed prompt is missing
- all repo-specific facts below are prompt assertions, not code-audited findings

Prompt-asserted current state to validate in the real repo:

- a MAS helper runtime is stubbed today
- the external runtime still assumes Node, localhost transport, and child-process helper launch
- container-scoped runtime workspace persistence already exists
- workspace file writes and user-library persistence already exist
- shader conversion and validation logic already exist but currently rely on script-oriented tooling

Locked facts:

- Apple requires Mac App Store apps to be sandboxed and forbids post-review executable feature changes through downloaded code.
- Apple supports app-bundled helper tools and XPC services in sandboxed macOS apps.
- The preferred MAS direction is a private XPC service plus bundled native Codex process, not the old Node or localhost topology.

File references:

- [prompt-seed.txt](/Users/jakekinchen/Documents/codex-xpc-bridge/prompt-seed.txt)
- [locked-facts-mas-runtime.md](/Users/jakekinchen/Documents/codex-xpc-bridge/docs/locked-facts-mas-runtime.md)

## Locked facts list

- `prompt-seed.txt` is the only local artifact describing the target system.
- The target repo path from the seed is unavailable, so no source-file-level verification is possible yet.
- The project packet must therefore be self-contained and implementation-ready without pretending existing code was inspected.
- MAS v1 must avoid Node, localhost transport, generic shell, and post-review runtime downloads.
- `CODEX_HOME` and all assistant state belong in the app container.

## Phase 2: Freeze the target architecture

## Required v1 architecture

- app shell owns transcript UI, approvals UI, and file pickers
- private bundled XPC service owns runtime session management
- XPC service launches and supervises the bundled native Codex binary
- Codex communicates over stdio with typed newline-delimited JSON envelopes
- all tools are app-owned, allowlisted, typed, and container-safe
- imported user files are copied into staged container workspace paths before conversion or validation
- saved WGSL artifacts and style memory persist under container storage

## Optional follow-up items

- warm process pooling across sessions
- broader provider matrix
- native reimplementation of any remaining conversion utilities
- additional bounded tool types beyond the WGSL-first surface

## Direct stdio versus XPC comparison

### Direct app -> Codex stdio

Pros:

- fewer moving parts
- less code at initial prototype stage

Cons:

- child-process failure modes land in the UI process
- weaker review story around process isolation and policy enforcement
- harder to keep entitlement-sensitive file access and tool mediation bounded

### App -> XPC -> Codex stdio

Pros:

- explicit helper boundary aligned with Apple platform guidance
- cleaner separation of UI, process supervision, and policy enforcement
- better restart, diagnostics, and bounded-tool control

Cons:

- extra transport layer
- more implementation overhead

Decision:

- choose `app -> XPC -> Codex stdio` for v1 and long-term MAS safety

## Phase 3: Define the bounded capability model

Allowed v1 tools:

- `import_shader`
- `convert_shader`
- `validate_shader`
- `capture_preview`
- `save_style_profile`
- `save_to_library`
- `read_workspace_file`
- `write_workspace_file`

Hard rejects:

- generic shell or exec
- arbitrary file traversal
- dynamic tool discovery
- unrestricted network access
- arbitrary binary execution from user-provided paths

Tool governance:

- each tool has typed inputs and normalized container paths
- every tool call is approved or auto-approved according to explicit policy
- the XPC service is the enforcement point
- the app shell remains the user-facing approval surface

See:

- [mas-bounded-tool-model.md](/Users/jakekinchen/Documents/codex-xpc-bridge/docs/app-store/mas-bounded-tool-model.md)

## Phase 4: Define the XPC bridge

Service responsibilities:

- expose typed runtime session methods to the app
- own Codex process lifecycle
- translate stdio envelopes to app-facing events
- enforce timeouts, cancellation, allowlist checks, and path policy
- capture logs and diagnostics to the app container

Process rules:

- launch Codex on first session start
- keep one warm process per active user session in v1
- tear down on app exit, explicit close, crash circuit breaker, or idle timeout
- perform one bounded automatic restart for recoverable child crashes

Transport rules:

- newline-delimited JSON envelopes
- unique `messageId` per session
- typed event set only
- invalid payloads terminate the active session

State rules:

- app owns durable transcript and UI state
- service owns volatile process and session routing state
- Codex owns provider interaction and prompt execution only

See:

- [mas-xpc-to-codex-stdio-architecture.md](/Users/jakekinchen/Documents/codex-xpc-bridge/docs/app-store/mas-xpc-to-codex-stdio-architecture.md)

## Phase 5: Define the parity contract

Parity baseline:

- supported MAS behavior should match the bounded user-visible assistant surface, not the legacy process topology

Must-match classes:

- transcript streaming
- tool visibility
- approval approve or reject behavior
- workspace persistence
- style-memory load and save
- shader conversion and validation
- preview capture
- library save
- provider status rendering
- crash and reconnect user messaging

Acceptable divergence:

- implementation process topology
- lower concurrency in v1
- stricter file import staging rules
- reduced provider surface if MAS auth or sandbox constraints require it

Intentionally unsupported:

- generic shell execution
- arbitrary user-specified executable launch
- dynamic tool installation
- localhost helper transport

See:

- [mas-parity-matrix.md](/Users/jakekinchen/Documents/codex-xpc-bridge/docs/app-store/mas-parity-matrix.md)

## Phase 6: Define the test strategy

The project requires explicit coverage in:

- unit tests
- integration tests
- end-to-end app runtime tests
- packaging and signing tests
- security and sandbox tests
- regression and reliability tests
- release-readiness gates

Tests to build first:

- fake Codex stdio fixture
- XPC envelope round-trip tests
- process manager launch, crash, and cancel tests
- allowlist and path confinement tests
- parity smoke harness

See:

- [mas-test-strategy.md](/Users/jakekinchen/Documents/codex-xpc-bridge/docs/plans/active/mas-test-strategy.md)

## Phase 7: Define implementation packets

Execution packets:

- Packet A: architecture contract extraction and shell/runtime seam
- Packet B: XPC service skeleton and typed transport
- Packet C: Codex process manager and stdio bridge
- Packet D: bounded tool allowlist and workspace/container integration
- Packet E: shader conversion and validation MAS-safe path
- Packet F: parity harness and test coverage
- Packet G: packaging, signing, release gates, and App Review docs

See:

- [mas-implementation-packets.md](/Users/jakekinchen/Documents/codex-xpc-bridge/docs/plans/active/mas-implementation-packets.md)

## Phase 8: Open questions and forced decisions

## Open question 1: Codex authentication path

Why it matters:

- if auth requires localhost callback behavior, the preferred MAS topology may need a constrained alternative flow or reduced provider scope

Missing evidence:

- real native Codex login behavior in MAS-like sandbox conditions

How to answer:

- run a signed staging build with diagnostic logging and attempt each in-scope provider mode

Safe default:

- MAS v1 ships only provider modes that work without localhost callbacks

Owner:

- runtime platform plus product

## Open question 2: Provider scope for MAS v1

Why it matters:

- parity promises must be limited to the provider set that is truly supportable under sandbox and review constraints

Missing evidence:

- provider-by-provider auth and session behavior under MAS-like packaging

How to answer:

- build a provider scorecard and classify each as `ship`, `follow-up`, or `blocked`

Safe default:

- support `api_key` first, treat other modes as optional until proven

Owner:

- product plus runtime platform

## Open question 3: Conversion stack composition

Why it matters:

- remaining dependency on mutable scripts or unsupported bundled toolchains could break the MAS story

Missing evidence:

- exact runtime dependencies for conversion and validation

How to answer:

- audit all conversion executables and scripts, then classify each as `bundle-safe`, `rewrite`, or `defer`

Safe default:

- WGSL-first and only conversion paths that can be made fully bundled and review-safe

Owner:

- graphics platform

## Open question 4: Protocol preservation versus protocol slimming

Why it matters:

- a direct reuse of the current app-server semantics may reduce migration cost but could preserve too much legacy complexity

Missing evidence:

- how much of the old protocol is truly required for the bounded MAS surface

How to answer:

- derive a minimal event matrix from the parity doc and compare it with the legacy protocol

Safe default:

- preserve only the event and tool semantics required by the bounded parity matrix

Owner:

- runtime platform

## Phase 9: Repo artifacts

Artifacts created by this packet:

- [2026-03-12-mas-xpc-stdio-bridge-implementation-plan.md](/Users/jakekinchen/Documents/codex-xpc-bridge/docs/plans/active/2026-03-12-mas-xpc-stdio-bridge-implementation-plan.md)
- [mas-xpc-to-codex-stdio-architecture.md](/Users/jakekinchen/Documents/codex-xpc-bridge/docs/app-store/mas-xpc-to-codex-stdio-architecture.md)
- [mas-test-strategy.md](/Users/jakekinchen/Documents/codex-xpc-bridge/docs/plans/active/mas-test-strategy.md)
- [mas-implementation-packets.md](/Users/jakekinchen/Documents/codex-xpc-bridge/docs/plans/active/mas-implementation-packets.md)
- [locked-facts-mas-runtime.md](/Users/jakekinchen/Documents/codex-xpc-bridge/docs/locked-facts-mas-runtime.md)
- [testflight-readiness.sh](/Users/jakekinchen/Documents/codex-xpc-bridge/scripts/release/testflight-readiness.sh)

## Risks and mitigations

- Risk: provider auth requires localhost callback behavior.
  - Mitigation: ship a reduced provider set and validate auth in signed staging before feature commitment.
- Risk: conversion toolchain still depends on mutable scripts or unsupported helpers.
  - Mitigation: freeze WGSL-first scope and audit all executables before Packet E implementation.
- Risk: protocol complexity slows XPC migration.
  - Mitigation: define the bounded parity matrix first and implement only the required event subset.
- Risk: packaging drift reintroduces Node or daemon payloads.
  - Mitigation: fail release gates on forbidden payload names, missing service paths, or localhost markers.

## Acceptance criteria

- the project has a documented MAS-safe target topology
- bounded tool behavior is defined and explicitly narrower than legacy open-ended agent execution
- the XPC bridge has concrete lifecycle, transport, cancellation, timeout, and restart rules
- tests and release gates are specific enough for engineers to implement without inventing policy
- unresolved decisions are explicit, owned, and time-bounded

## Recommended next packet

Start with Packet A.

Reason:

- it extracts the contract the app shell depends on before XPC transport and process supervision are built
- it prevents Packet B and Packet C from accidentally encoding legacy topology assumptions
