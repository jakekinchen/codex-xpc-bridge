# 2026-03-12 MAS XPC Stdio Bridge Implementation Plan

Status: Active
Owner: Technical PM
Audience: App team, runtime platform, release engineering, security review

## Goal

Ship a Mac App Store-safe and open-source-reusable bridge using:

`app shell -> private bundled XPC service -> bundled native Codex binary over stdio`

This plan is no longer framed as a bounded shader assistant implementation packet. The current codebase already proves the app/XPC/process topology, packaging, and integration path. The remaining work is a separation and hardening pass so the package can be reused by any MAS-safe Codex app-server host, not just the current demo surface.

## Current repository status

Confirmed locally:

- the package shape is already generic at the app/XPC/process boundary
- the shared contract, XPC seam, process manager, runtime locator, container pathing, and packaging path all exist
- `swift test` is green today, but current tests validate the existing demo-domain tool model rather than the final generic bridge contract

Confirmed implementation gaps to close before calling the package reusable:

- tool identity is still a closed domain enum rather than an opaque host-owned ID
- tool execution is still package-owned instead of host-injected
- approval policy exists but is not yet authoritative in the broker
- restart policy exists but is not yet wired into live broker behavior
- malformed stdout currently logs and continues instead of terminating the active session
- timeout policy is not yet implemented across runtime, approval, tool, and XPC request boundaries
- `Sources/codex/main.swift` is still both demo runtime and fixture instead of being explicitly fixture-only

Current implementation slice underway:

- introduce a string-backed `ToolID` compatibility layer in the contract while preserving existing call sites
- inject tool handling into the broker or session through a factory seam instead of constructing `DemoToolExecutor` directly
- treat this as the start of Packet A plus Packet B, not a complete genericization pass

## Phase 1: Freeze the reusable bridge boundary

The package-owned boundary should remain generic and reusable:

- XPC `send(Data)` / `receiveEvent(Data)` transport only
- request, reply, and event envelopes
- Codex child-process launch and supervision
- runtime binary location and bundle wiring
- container-scoped `CODEX_HOME` and workspace roots
- diagnostics and log capture
- session lifecycle and transcript streaming

The package should not own app-domain tool semantics beyond fixture/default implementations.

## Phase 2: Refactor the tool contract to opaque IDs

### Required contract change

Replace the current closed tool enum model with opaque string-backed tool IDs.

Target shape:

- tool identity is host-owned and string-backed
- arguments remain typed JSON dictionaries
- results remain typed JSON dictionaries plus artifact paths
- no package-level assumption that tool IDs correspond to a specific app domain

Required migration rules:

- treat this as a deliberate protocol migration, not a search-and-replace
- update contract, session store, broker, fixture runtime, and tests together
- preserve newline-delimited JSON transport and envelope structure
- keep field names stable where possible during the first migration slice to limit churn
- prefer compatibility constants during Packet A so the repo can migrate incrementally without breaking every call site at once

### Consequence

The current shader-oriented IDs become legacy fixture/default IDs, not package-defining API.

## Phase 3: Make tool handling host-injected

### Required separation

The broker must not construct a concrete package-owned tool executor directly.

The service layer should depend on injected host-facing seams such as:

- `ToolHandling`
- `ToolApprovalPolicy`
- optional host capability or descriptor metadata

Minimum first-pass requirement:

- inject a tool-handling interface into the broker or session
- keep the current `DemoToolExecutor` only as a default or fixture implementation
- remove any requirement that hosts fork package internals to change tool behavior
- express injection through a factory seam so per-session tool handlers can still be constructed with runtime paths and resolver context

## Phase 4: Make policy authoritative in the service

### Approval policy

The service is the authority.

Rules:

- runtime-emitted `requiresApproval` is advisory only
- the broker recomputes approval requirement from host policy
- deny-by-default behavior should be the baseline for unknown or undeclared tools
- app shell remains the approval UI
- XPC service remains the enforcement point

### Restart policy

The live broker must use the reusable restart policy object instead of ad hoc counters.

Rules:

- configurable restart budget
- configurable restart window
- bounded recovery only
- clear user-visible terminal failure state after budget exhaustion

### Timeout policy

The service must enforce explicit timeout rules for:

- process startup
- prompt dispatch
- tool execution
- approval waits
- child silence or stalled stdio
- XPC request lifetimes where appropriate

## Phase 5: Harden malformed-child behavior

Malformed or unknown child stdout is a terminal protocol failure for the active session.

Rules:

- invalid JSON or unknown message shape on stdout terminates the active session
- termination is surfaced as runtime error and interruption state to the app
- if restart policy allows recovery, restart is attempted through the same policy path
- child stderr remains diagnostic only unless elevated by explicit policy

This closes the current gap between the architecture docs and live code.

## Phase 6: Demote the demo runtime to fixture-only

`Sources/codex/main.swift` remains useful, but only as:

- fixture runtime for integration tests
- demo binary for packaging smoke tests
- example bounded child protocol implementation

It should not define the package's reusable semantics.

Required framing:

- keep demo workflow behavior out of the generic public contract
- label demo tools and behavior as fixture/default behavior in docs and tests
- ensure hosts can replace runtime/tool behavior without changing transport/process layers

## Phase 7: Test strategy for the refactor

The current test suite is a strong base, but the refactor requires new coverage before release.

### Must-add tests

- contract migration tests for opaque tool IDs
- broker tests proving service-enforced approval policy overrides runtime hints
- broker tests proving injected tool handlers are used instead of package-owned construction
- restart-policy integration tests using live broker behavior
- malformed-stdout termination tests
- timeout expiry tests for startup, tool execution, and approval wait boundaries
- fixture-runtime tests proving the demo runtime remains fixture-only and not package-defining

### Keep existing coverage

- protocol encode/decode coverage
- path confinement coverage
- packaging and bundle-assembly coverage
- end-to-end broker/runtime integration coverage

## Phase 8: Explicit implementation packet ordering

Execution packets are reordered to match the actual refactor dependencies.

- Packet A: protocol migration to opaque tool IDs
- Packet B: inject tool handling and default fixture executor
- Packet C: make approval policy authoritative in broker
- Packet D: wire live restart policy and timeout policy
- Packet E: malformed-stdout hard-fail and recovery semantics
- Packet F: fixture-only runtime cleanup and contract-facing docs
- Packet G: hardening test coverage and release-readiness gates
- Packet H: packaging/review verification and open-source cleanup

### Packet sequencing rules

- do not start timeout/restart hardening before the broker has injectable policy seams
- do not claim open-source genericity before tool IDs and tool handling are decoupled from the demo domain
- do not expand host surfaces until malformed-stream handling and failure semantics are fixed

## Phase 9: Open decisions to lock before or during implementation

### Decision 1: protocol evolution mode

Choose one:

- explicit breaking v2 contract now
- compatibility bridge with legacy fixture IDs during migration

### Decision 2: approval policy baseline

Choose one:

- deny-by-default for unknown tools
- host-configured fallback rule

Recommendation:

- deny-by-default in service

### Decision 3: timeout scope

Choose one:

- per-session only
- per-operation only
- both per-session and per-operation

Recommendation:

- both, with explicit approval-wait timeout and child-silence timeout

### Decision 4: default tool implementation story

Choose one:

- ship a fixture/default executor in-package
- require hosts to always provide tool handling

Recommendation:

- keep a fixture/default executor for tests and demo packaging, but do not make it the package-defining behavior

## Immediate implementation order

1. patch the contract and dependent state types to use opaque tool IDs
2. introduce injected tool-handling seams while keeping the current executor as the default fixture path
3. move broker approval decisions to service-owned policy
4. replace ad hoc restart behavior with `RestartPolicy`
5. implement timeout and malformed-stream termination semantics
6. relabel and contain the demo runtime as fixture-only
7. extend tests to prove the new hardening and generic seams

## Reference docs

- [mas-xpc-to-codex-stdio-architecture.md](/Users/jakekinchen/Documents/codex-xpc-bridge/docs/app-store/mas-xpc-to-codex-stdio-architecture.md)
- [mas-bounded-tool-model.md](/Users/jakekinchen/Documents/codex-xpc-bridge/docs/app-store/mas-bounded-tool-model.md)
- [mas-test-strategy.md](/Users/jakekinchen/Documents/codex-xpc-bridge/docs/plans/active/mas-test-strategy.md)
- [mas-implementation-packets.md](/Users/jakekinchen/Documents/codex-xpc-bridge/docs/plans/active/mas-implementation-packets.md)
