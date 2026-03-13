# 2026-03-09 Swift Codex Control Plane Plan

## Status

- Date: 2026-03-09
- Owner: macOS App Shell / Runtime Integration
- Status: Proposed baseline
- Decision class: Swift-side architecture

## Purpose

Define the Swift control plane that owns the app-side runtime seam for the MAS-safe assistant path. The control plane is responsible for session orchestration, approval routing, persistence integration, diagnostics, and typed communication with the private XPC service.

The control plane exists to keep Swift UI simple and deterministic while allowing the XPC service to manage Codex process lifecycle and stdio transport.

## Architectural Boundary

The target topology is:

- Swift UI and app features
- Swift runtime client and control plane
- Private bundled XPC service
- Bundled native Codex binary over stdio

The app shell does not manage the Codex child process directly in v1. That responsibility belongs to the XPC service so the app-facing layer remains stable and reviewable.

## Goals

- Present a stable app-owned runtime interface to Swift UI.
- Keep assistant state, approvals, and workspace interactions coherent across service interruptions.
- Isolate Swift UI from transport details and process management.
- Make persistence and diagnostics first-class responsibilities of the app shell.

## Non-Goals

- Expose `Process` handling or pipe management to Swift UI.
- Let UI code speak raw XPC envelopes.
- Encode product policy in views.
- Recreate a generic RPC bus.

## Control Plane Responsibilities

### Session orchestration

- Create, resume, and terminate assistant sessions
- Maintain session and conversation identifiers
- Map user actions to protocol requests
- Track terminal versus recoverable runtime states

### Approval coordination

- Receive `approval_required` events from the runtime client
- Present approval UI with human-readable context
- Enforce single-resolution semantics per approval token
- Persist any approval audit trail needed for diagnostics

### Transcript and event store

- Merge assistant deltas into visible transcript state
- Persist transcript artifacts or reconstruction metadata as required
- Ensure tool-call and tool-result visibility remains aligned with transcript order

### Persistence integration

- Resolve container paths for `CODEX_HOME`, workspace storage, style memory, and user library outputs
- Provide file import handoff for security-scoped user selections
- Enforce path confinement before requests cross the XPC boundary

### Diagnostics and observability

- Surface provider status and runtime health to UI
- Capture service interruption, crash, restart, and timeout events
- Attach correlation identifiers to logs that span UI, XPC, and tool execution

## Proposed Swift Components

### `AssistantRuntimeCoordinator`

Primary orchestration facade used by app features.

Responsibilities:

- Session lifecycle
- Prompt submission
- Cancellation
- Approval routing
- Runtime health reporting

### `CodexXPCClient`

Typed wrapper around `NSXPCConnection`.

Responsibilities:

- Encode requests into the XPC envelope
- Decode XPC events into Swift domain events
- Handle invalidation and interruption callbacks
- Reconnect according to policy

### `AssistantSessionStore`

Single source of truth for UI-visible session state.

Responsibilities:

- Transcript aggregation
- Tool activity ordering
- Pending approval state
- Recoverable versus terminal error state

### `ApprovalCoordinator`

Owns approval presentation and decision dispatch.

Responsibilities:

- Serialize approval requests
- Prevent duplicate resolutions
- Record denial and timeout states

### `RuntimePathResolver`

Owns container path resolution and confinement checks.

Responsibilities:

- Determine `CODEX_HOME`
- Resolve workspace root
- Resolve style-memory and library paths
- Validate imported file destinations

## What Lives Outside the Swift Control Plane

### XPC service responsibilities

- Codex process launch, supervision, restart, and teardown
- Stdio framing and translation
- Tool invocation dispatch to app-owned implementations exposed by the service boundary
- Child-process stdout and stderr diagnostics capture

### Codex responsibilities

- Assistant reasoning
- Provider-specific runtime logic
- Requesting bounded tool actions through the MAS-safe tool surface

## Concurrency Model

- The session store and approval coordinator must be serialized by actor or equivalent single-owner discipline.
- UI updates must be marshaled onto the main actor only after protocol events have been normalized.
- XPC callbacks must never mutate UI state directly.
- Cancellation must be cooperative: prompt cancellation updates Swift state immediately and then propagates to the service.

## Persistence Contract

- `CODEX_HOME` is app-container scoped and stable across relaunch.
- Workspace files are persisted under a container-owned workspace root.
- Imported user files are copied or materialized into the workspace before conversion or validation.
- Style memory and saved shader outputs are user data, not bundle resources.

## Failure Handling

- XPC interruption transitions the runtime to recoverable degraded state.
- Child-process crash is surfaced distinctly from tool failure.
- Approval dialogs are invalidated if the owning session ends or becomes unrecoverable.
- Stale session identifiers are rejected before UI mutation.

## Dependencies

- Stable runtime protocol envelopes
- XPC interface definitions
- Workspace and library services
- App-level logging and telemetry
- MAS-safe provider authentication decision

## Testing Implications

- Unit tests for session-store event reduction
- Unit tests for path resolution and confinement
- Unit tests for approval single-resolution behavior
- Integration tests for XPC invalidation and reconnection
- End-to-end tests for transcript, tool activity, and persistence across relaunch

## Open Issues

- Whether session reconstruction after restart is transcript-based or runtime-state-based
- Whether provider status should be cached independently of session lifecycle
- How much diagnostic stderr is surfaced to UI versus logs only
- Whether multi-window concurrency requires one coordinator per window or a shared runtime pool

## Acceptance Criteria

- Swift UI depends only on app-owned domain types, not raw transport payloads.
- Session state, approvals, and transcript updates survive expected interruption paths.
- Container path rules are enforced before requests reach the XPC service.
- Failure states are specific enough to drive recovery UI and release diagnostics.
