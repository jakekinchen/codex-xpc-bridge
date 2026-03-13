# 2026-03-09 MAS Agent Service Parity Plan

## Status

- Date: 2026-03-09
- Owner: Assistant Runtime / macOS Platform
- Status: Proposed baseline
- Decision class: Architecture and parity contract

## Purpose

Define the bounded parity contract for a Mac App Store-safe assistant runtime that replaces the legacy external-runtime topology with an in-bundle XPC service that owns a bundled native Codex process over stdio.

This document is the parity baseline. It does not prescribe every implementation detail. It defines what user-visible behavior must remain comparable, what divergence is acceptable, and what capabilities are intentionally removed from the MAS lane.

## Context

The MAS runtime path must satisfy all of the following:

- Preserve the supported assistant experience for shader-centric workflows.
- Eliminate dependency on bundled Node, `daemon/dist`, `daemon/node_modules`, localhost servers, and child-process helper launch from the app shell.
- Replace the external-runtime seam with a private XPC boundary that is easier to explain to App Review and easier to constrain under App Sandbox.
- Keep all mutable runtime state in the app container via `CODEX_HOME` and container-scoped workspace/library paths.
- Bound tool usage to a typed allowlist owned by the app product, not by open-ended agent discovery.

Primary policy dependencies:

- App Review Guidelines section 2.5.2 requires software to be self-contained and forbids code that introduces or changes features after review.
- App Sandbox guidance permits a sandboxed app to include helper tools and XPC services when packaged and signed as part of the app.
- XPC service guidance establishes the intended pattern for privileged separation and lifecycle management inside a bundled macOS app.

Source links:

- <https://developer.apple.com/app-store/review/guidelines/>
- <https://developer.apple.com/documentation/security/app-sandbox>
- <https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox/>
- <https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html>
- <https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html>

## Problem Statement

The legacy assistant stack assumed an external or helper-oriented topology that is not appropriate for the MAS lane:

- app shell -> Node-backed daemon
- daemon opens localhost transport
- daemon or helper launches subordinate tools
- runtime surface is broader than review-safe MAS scope

That topology is mismatched with the MAS requirements because it is harder to justify under App Review, harder to sandbox tightly, and easier to drift into unrestricted execution paths.

## Goals

- Ship a MAS-safe assistant runtime seam with user-visible parity for the bounded surface.
- Preserve streaming assistant transcripts, tool visibility, approvals, persistence, and shader-centric save/apply flows.
- Make the MAS assistant path legible as a fixed, shipped, typed product feature.
- Keep workspace, style memory, and saved shader outputs container-scoped and durable across launches.
- Provide a parity scorecard and release gates that verify behavior, not only bundle contents.

## Non-Goals

- Preserve the legacy process topology.
- Support arbitrary shell commands, generic exec, or dynamic tool registration.
- Support unrestricted filesystem traversal outside the container and explicit user grants.
- Require `com.apple.security.network.server` for v1.
- Treat every external-runtime feature as in-scope for MAS v1.

## Locked Decisions

- The MAS runtime seam is `App Shell -> Private XPC Service -> Bundled Native Codex Binary over stdio`.
- The app shell does not launch Codex directly in v1. The XPC service owns Codex lifecycle.
- The transport is stdio, not localhost HTTP or WebSocket.
- All tool invocation exposed to Codex is typed, allowlisted, and implemented by app-owned runtime components.
- `CODEX_HOME`, workspace state, and user library persistence live in the app container.
- WGSL-first is the supported MAS content scope unless later evidence proves that a wider conversion surface is review-safe and operationally bounded.

## Supported Surface

The following behavior is in scope for parity:

- Session start and teardown
- Transcript streaming
- Tool-call visibility
- Tool-result visibility
- Approval-required flow
- Approval approve/reject behavior
- Workspace file read and write within container-scoped paths
- User style memory read and write
- Shader import, conversion, validation, preview capture, and library save on the bounded MAS surface
- Error rendering and recovery messaging
- Crash or interruption recovery with explicit user-visible reconnection semantics

## Intentionally Unsupported in MAS v1

- Arbitrary shell execution
- Arbitrary executable launch from user-controlled paths
- Dynamic tool discovery
- Generic network server behavior
- Open-ended filesystem browsing outside the workspace, container, or explicit user-selected imports
- Feature lanes that require post-review toolchain download or mutable code payloads

## Parity Classification

### Must-match

- Assistant transcript streaming cadence and completion semantics
- Visibility of tool activity and tool outcomes in the transcript
- Explicit approval prompts before sensitive tool actions
- Durable workspace persistence across relaunch
- Durable user style memory and saved library outputs
- Predictable error states for timeout, denial, and child-process interruption

### Acceptable divergence

- Process topology and implementation language
- Lower maximum concurrency in the MAS lane
- Narrower provider matrix if auth or provider-specific requirements are not MAS-safe
- Reduced tool inventory as long as the supported user-facing flows remain intact

### Intentionally unsupported

- Legacy localhost debugging hooks
- Open-ended tooling or shell lanes
- Any provider flow that cannot be made self-contained and review-safe

## Required Architecture Characteristics

- XPC service is bundled privately inside the app and not exposed as a general-purpose service boundary.
- Codex binary is bundled and signed with the app.
- Codex is launched on demand per active session group and torn down when idle or when the app exits.
- App-facing runtime APIs are stable and typed.
- Transport envelopes preserve event ordering, correlation identifiers, and approval suspension semantics.
- Tool execution is app-owned and scoped to container paths or explicit user grants.

## Dependencies

- Stable app-facing runtime protocol
- Stable approval model and transcript event mapping
- Stable workspace path contract
- Determination of MAS-safe auth story for provider modes
- Packaging rules that verify the absence of Node/daemon/localhost dependencies

## Testing Implications

- Parity must be tested behaviorally, not only structurally.
- Test fixtures need a fake Codex stdio binary that exercises event streaming, approvals, tool requests, failures, and invalid payloads.
- The parity harness must score must-match behavior separately from acceptable divergence.
- Packaging tests must verify the intended bundle contents and the absence of forbidden legacy payloads.

## Risks

- Provider auth may rely on flows that are not MAS-safe.
- Legacy UI expectations may assume broader tool semantics than the bounded allowlist can support.
- The current TypeScript event model may include loosely typed states that need a stricter MAS contract.

## Open Issues

- Final provider-mode scope for MAS v1
- Whether any non-WGSL import lanes are supportable without broadening runtime risk
- Whether preview capture stays in-process with app rendering or moves behind a tool boundary
- Whether a single warm Codex child per app window is sufficient, or if per-conversation isolation is required

## Exit Criteria

- A parity matrix exists with explicit must-match, acceptable divergence, and unsupported classifications.
- The XPC bridge architecture is documented and reviewed.
- The bounded tool model is documented and reviewed.
- The test plan includes parity scoring, packaging gates, and security constraints.
- Release readiness includes a MAS-specific assistant smoke suite and App Review notes.
