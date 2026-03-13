# MAS Implementation Packets

Date: 2026-03-12
Status: Ready for assignment
Owner: Technical PM

## Packet A: Architecture contract extraction and shell/runtime seam

Objective:

- define the typed seam between the app shell and the new MAS runtime path

File and module ownership:

- app-facing runtime protocol definitions
- session and approval domain models
- shell-side runtime adapter interfaces

Dependencies:

- none

Tests to write first:

- contract encode or decode tests
- app-facing event translation tests

Acceptance criteria:

- the shell can talk to an abstract runtime interface with no Node or localhost assumption
- approval and transcript events have typed models
- unsupported open-ended capabilities are absent from the seam

Likely risks:

- leaking old helper assumptions into the new API
- mixing UI state concerns with process state concerns

Must not change:

- user-visible approval semantics without explicit product signoff

## Packet B: XPC service skeleton and typed transport

Objective:

- build the private XPC service boundary and typed request or event transport

File and module ownership:

- XPC service target
- NSXPC interfaces
- service bootstrap and connection management
- request envelope codec

Dependencies:

- Packet A

Tests to write first:

- XPC connection smoke tests
- request envelope round-trip tests
- invalid payload rejection tests

Acceptance criteria:

- app shell can create a session through XPC
- service handles disconnect and invalidation deterministically
- typed transport is stable under concurrent event flow

Likely risks:

- NSXPC interface shape too coarse for streaming
- lifecycle mismatch between app expectations and service launch behavior

Must not change:

- bundled private helper model

## Packet C: Codex process manager and stdio bridge

Objective:

- add the bundled native Codex process supervisor behind the XPC service

File and module ownership:

- process supervisor
- stdin/stdout/stderr pipe management
- restart and circuit breaker logic
- environment construction including `CODEX_HOME`

Dependencies:

- Packet B

Tests to write first:

- child process launch and timeout tests
- crash and restart tests
- cancellation tests

Acceptance criteria:

- service launches Codex on demand
- structured deltas stream through to the app
- crash, restart, and shutdown behaviors are deterministic

Likely risks:

- native Codex auth behavior in MAS
- protocol mismatch between expected and actual stdio semantics

Must not change:

- no direct app-process child supervision

## Packet D: Bounded tool allowlist and workspace/container integration

Objective:

- implement the closed MAS tool surface with container-safe persistence

File and module ownership:

- allowlist registry
- tool executors
- workspace confinement helpers
- import staging and bookmark consumption
- style-memory and library persistence adapters

Dependencies:

- Packet A
- Packet C

Tests to write first:

- allowlist enforcement
- path confinement and symlink escape tests
- style-memory persistence tests

Acceptance criteria:

- only approved tools execute
- all writes stay in the container or user-granted locations
- tool results rejoin the transcript flow cleanly

Likely risks:

- hidden filesystem escape paths
- UI mismatch in approval and persistence behavior

Must not change:

- no generic shell or exec surface

## Packet E: Shader conversion and validation MAS-safe path

Objective:

- ship WGSL-first conversion, validation, and preview within the bounded tool model

File and module ownership:

- conversion wrapper
- validation pipeline
- preview capture pipeline
- library save adapter

Dependencies:

- Packet D

Tests to write first:

- conversion happy path
- validation failure reporting
- preview capture timeout tests

Acceptance criteria:

- imported shaders can be converted, validated, previewed, and saved without legacy daemon topology
- failures produce app-facing structured errors

Likely risks:

- remaining dependency on scripts or toolchains that are not MAS-safe
- performance regressions under repeated conversions

Must not change:

- WGSL-first scope for v1

## Packet F: Parity harness and test coverage

Objective:

- prove bounded parity and runtime reliability

File and module ownership:

- fake Codex fixture
- integration harness
- parity scorecard
- smoke suite

Dependencies:

- Packets A through E

Tests to write first:

- happy-path stdio harness
- approval round-trip E2E test
- crash recovery test

Acceptance criteria:

- must-match parity items are all green
- release evidence artifacts are produced in CI

Likely risks:

- parity claims outpace actual coverage
- fixture diverges from real Codex behavior

Must not change:

- release requires evidence, not narrative assurance

## Packet G: Packaging, signing, release gates, and App Review docs

Objective:

- package the MAS-safe runtime and prove bundle hygiene

File and module ownership:

- build and packaging scripts
- entitlement manifests
- bundle inspection gates
- reviewer notes and release checklist

Dependencies:

- Packets B through F

Tests to write first:

- bundle path presence checks
- forbidden payload absence checks
- entitlement inspection checks

Acceptance criteria:

- the bundle contains the XPC service and bundled Codex binary
- the bundle excludes Node, daemon payloads, localhost dependencies, and mutable bundled scripts
- App Review notes explain the bounded assistant model honestly

Likely risks:

- signing chain mistakes for nested helpers
- accidental reintroduction of legacy payloads

Must not change:

- no post-review helper downloads or dynamic code paths

## Recommended execution order

1. Packet A
2. Packet B
3. Packet C
4. Packet D
5. Packet E
6. Packet F
7. Packet G

## Program-level completion definition

The project is ready to ship only when all packets meet acceptance criteria, all must-match parity items pass, and the release gate evidence proves the MAS runtime no longer depends on the legacy Node or localhost topology.
