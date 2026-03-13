# MAS XPC Runtime Test Strategy

Date: 2026-03-12
Status: Proposed
Owner: Runtime QA + Platform

## Goal

Prove that the MAS-safe assistant runtime preserves the bounded supported surface while remaining sandbox-safe, packaging-safe, and operationally reliable.

## Test principles

- test the XPC seam, not just the Codex child in isolation
- prove bounded behavior with explicit negative tests
- treat packaging and sandbox policy as first-class release gates
- collect evidence artifacts for every release candidate
- never claim parity without a scorecard

## Test environments

- local developer debug build with a fake Codex binary
- CI simulator or host-driven integration runner for XPC and process supervision tests
- signed staging build with real bundle inspection
- MAS-preflight build with release gate script and artifact capture

## Unit tests

## XPC request and response envelope behavior

Scenarios:

- encode and decode every request type
- reject unknown `type`
- reject version mismatch
- reject missing `sessionId`
- preserve ordering across multiple deltas

Evidence:

- golden JSON fixtures
- protocol decode failure snapshots

## Codex process manager behavior

Scenarios:

- launch happy path
- startup timeout
- broken stdin pipe on send
- stdout close before completion
- stderr capture truncation
- idle timeout teardown
- explicit shutdown

Evidence:

- process lifecycle logs
- state-machine transition assertions

## `CODEX_HOME` path selection

Scenarios:

- container path default
- override rejection in MAS mode
- path creation on first launch
- migration from missing directory

## Container path resolution

Scenarios:

- workspace root resolution
- import staging root resolution
- style-memory root resolution
- library root resolution
- diagnostics root resolution

## Workspace path confinement

Scenarios:

- permit writes under workspace root
- reject `..` traversal
- reject symlink escape
- reject absolute paths outside approved roots

## Tool allowlist enforcement

Scenarios:

- accept every supported tool
- reject unsupported tool names
- reject dynamic tool metadata
- reject generic shell or exec requests
- reject unrestricted network access requests

## Timeout and cancellation behavior

Scenarios:

- prompt cancel before first delta
- cancel during streaming
- cancel during tool execution
- tool timeout returns structured failure
- child kill after cancellation grace window

## Crash and restart logic

Scenarios:

- one child crash with successful restart
- repeated crash enters circuit breaker
- pending approvals invalidated on restart
- session recreation required after reconnect

## Event translation behavior

Scenarios:

- Codex `delta` becomes app transcript stream event
- tool call request becomes approval-required UI event
- tool result maps back into completion event
- child stderr warning becomes redacted diagnostic event

## Integration tests

Use a fake Codex binary that speaks the stdio envelope and can be scripted through fixtures.

## Happy-path end-to-end runtime flow

Scenarios:

- `startSession`
- `sendPrompt`
- streamed deltas
- tool call request
- approval round-trip
- tool result
- `turnCompleted`

## Broken pipe and invalid payload handling

Scenarios:

- stdout malformed JSON
- stdout message missing required fields
- child exits mid-turn
- service emits `runtimeInterrupted`
- restart and session recreation

## Tool approval round-trip

Scenarios:

- approval accepted
- approval rejected
- approval expired
- duplicate approval response ignored

## Container-scoped persistence flows

Scenarios:

- write workspace file
- read workspace file
- save style memory
- save library artifact
- relaunch and verify persistence is visible to the app

## Imported file handling and bookmarks

Scenarios:

- user-selected file copied into import staging
- security-scoped access opened only for copy window
- bookmark restoration for deferred operation
- post-copy processing uses staged path, not original external path

## End-to-end app runtime tests

These tests should exercise the actual app shell, the XPC service, and a real or simulated Codex child.

## Required E2E coverage

- app launch to first prompt response
- assistant transcript streaming
- approval banner presentation and approve or reject behavior
- tool-call visibility in transcript timeline
- preview generation flow
- save-to-library completion flow
- style-memory read then write flow
- shader conversion flow
- shader validation flow
- app relaunch with restored session metadata
- graceful teardown while work is active

## Packaging and signing tests

Scenarios:

- expected XPC service exists in the app bundle
- expected Codex binary exists at the approved bundle path
- bundle contains no `node`, `node_modules`, `daemon/dist`, or legacy helper payloads
- codesign is valid for app, XPC service, and bundled binary
- sandbox entitlements are present only where intended
- no `com.apple.security.network.server` entitlement unless explicitly approved
- no localhost transport markers in packaged MAS runtime assets

Evidence:

- `codesign --display --entitlements`
- bundle path manifest
- release gate script logs

## Security and sandbox tests

Scenarios:

- no writes outside container or user-granted locations
- no symlink traversal escape from workspace
- no arbitrary executable path launch
- no shell access path reachable through tool surface
- no unexpected network server bind attempt
- security-scoped bookmarks are required for deferred access to user-selected locations

## Regression and reliability tests

Scenarios:

- repeated conversion and validation cycles
- restart after Codex crash
- service interruption and session recreation
- approval flow recovery after reconnect
- cancellation mid-stream
- shutdown with active work
- log redaction after provider error

## Release-readiness gates

Every release candidate must produce:

- parity scorecard
- MAS assistant smoke suite results
- bundle inspection report
- sandbox and entitlement report
- XPC and Codex lifecycle logs
- list of intentionally unsupported behaviors

Mandatory gates:

- all unit and integration suites pass
- E2E smoke suite passes on signed staging build
- release gate script passes
- no critical or high severity open risk without waiver
- parity score for v1 must-match items is 100 percent

## Test fixtures and tooling to build first

- fake Codex stdio server fixture
- XPC contract fixture harness
- workspace confinement test helpers
- bundle inspection helper for packaging tests
- approval flow simulator for E2E tests

## Ownership

- Runtime Platform: unit and integration coverage
- App team: E2E UI and approval flow coverage
- Release engineering: packaging and signing gates
- Security owner: sandbox and negative-path validation

## Exit criteria

The runtime is release-candidate ready only when the bounded supported surface is proven in a signed MAS-style bundle and all policy, packaging, sandbox, and recovery gates have recorded evidence artifacts.
