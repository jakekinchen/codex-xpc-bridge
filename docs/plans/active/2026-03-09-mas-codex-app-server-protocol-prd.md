# 2026-03-09 MAS Codex App-Server Protocol PRD

## Status

- Date: 2026-03-09
- Owner: Assistant Runtime / Protocol
- Status: Proposed baseline
- Decision class: Runtime protocol

## Purpose

Define the protocol contract between the Swift app shell and the MAS-safe Codex runtime lane. The goal is to preserve assistant interaction semantics while moving the runtime behind a private XPC service that brokers a bundled native Codex process over stdio.

This PRD treats the existing external runtime semantics as source behavior to preserve where user-visible parity matters. It does not require process or implementation parity.

## Product Requirement

The MAS protocol layer must support:

- Session creation and teardown
- Conversation-scoped prompt submission
- Incremental transcript streaming
- Tool-call proposals and approval pauses
- Tool results and completion
- Error signaling with actionable categories
- Service interruption and child-process restart reporting

The MAS lane must not expose raw shell access, dynamic tool discovery, or open-ended request passthrough.

## Protocol Layers

### Layer 1: App-facing typed runtime API

Swift UI and app services talk to a typed runtime client. This layer is versioned by Swift types, not ad hoc dictionaries.

Responsibilities:

- Create and resume assistant sessions
- Send prompts and cancellation requests
- Surface transcript deltas and structured events
- Present approvals and forward user decisions
- Expose service state and diagnostics for UI rendering

### Layer 2: XPC envelope

The app-facing runtime client communicates with the private XPC service using a narrow set of request and event envelopes.

Requirements:

- Stable request identifiers
- Session identifiers and conversation identifiers
- Ordering guarantees within a session
- Explicit terminal states
- Restart or interruption events
- Typed payload validation at the XPC boundary

### Layer 3: Codex stdio protocol

The XPC service speaks the native Codex app-server lane over stdio. The XPC service is the compatibility boundary that translates Codex-native semantics into the app-facing event model.

## Protocol Goals

- Preserve streaming UX
- Preserve approval semantics
- Preserve tool visibility and result visibility
- Keep the app-facing interface stable even if Codex-native payload shapes evolve
- Fail closed when unexpected payloads arrive

## Non-Goals

- Expose raw Codex process internals to Swift UI
- Make the XPC service a generic RPC tunnel
- Preserve every external-runtime event if the event has no user-visible value
- Let Codex dynamically invent new MAS tools

## Required Envelope Types

### Requests

- `create_session`
- `resume_session`
- `send_prompt`
- `cancel_operation`
- `resolve_approval`
- `terminate_session`
- `query_runtime_status`

### Responses

- `ack`
- `rejected`
- `runtime_status`

### Events

- `session_ready`
- `assistant_delta`
- `assistant_message_completed`
- `tool_call_requested`
- `approval_required`
- `approval_resolved`
- `tool_call_started`
- `tool_call_completed`
- `tool_call_failed`
- `runtime_warning`
- `runtime_error`
- `session_ended`
- `service_interrupted`
- `service_recovered`

## Envelope Requirements

Every request and event must carry:

- `protocolVersion`
- `requestId` or `eventId`
- `sessionId`
- `conversationId` where applicable
- `timestamp`
- `kind`

When tool activity is involved, envelopes must additionally carry:

- `toolName`
- `toolInvocationId`
- `approvalState`
- `workspaceScope`

## Ordering and Delivery Rules

- Requests are processed in-order per session.
- Events are emitted in-order per session except diagnostics, which may be coalesced.
- Exactly one terminal event must end a prompt operation: completion, cancellation, or error.
- Approval pauses suspend downstream tool execution until a user decision is received or a timeout is reached.
- Duplicate approval decisions are ignored after terminal resolution.

## Approval Model

Approval is first-class protocol state. It is not a UI-only concern.

Rules:

- Only tools classified as approval-requiring can emit `approval_required`.
- Approval payloads must include a human-readable reason, affected resources, and allowed actions.
- Rejection returns a structured denial result to the assistant instead of a transport error.
- Approval timeouts return a structured timeout result with an explicit retry path.

## Tool Surface

Only bounded, typed tools are addressable through the MAS protocol. Initial allowlist:

- `import_shader`
- `convert_shader`
- `validate_shader`
- `capture_preview`
- `save_style_profile`
- `save_to_library`
- `read_workspace_file`
- `write_workspace_file`

Tool names are stable product API. Any addition requires explicit review and updated App Review notes.

## Error Taxonomy

The app-facing layer must collapse runtime failures into a bounded taxonomy:

- `transport_error`
- `protocol_violation`
- `approval_denied`
- `approval_timeout`
- `tool_timeout`
- `tool_input_rejected`
- `workspace_access_denied`
- `runtime_crash`
- `service_interruption`
- `provider_unavailable`

Errors may include diagnostic details, but UI state and retry behavior must be keyed off the bounded taxonomy.

## Restart and Recovery Semantics

- XPC interruption does not silently lose session state in the UI.
- If the XPC service can restart Codex and rebind the active session, it emits `service_recovered`.
- If the session cannot be recovered, the app receives `runtime_error` followed by `session_ended`.
- Pending approvals and tool actions are invalidated on unrecoverable child-process crash.

## Security and Policy Constraints

- The protocol must never expose raw command execution.
- All filesystem references must resolve to container-scoped paths or explicit user-granted imports.
- No request type may instruct the XPC service to open a listener socket.
- No protocol field may accept an arbitrary executable path.

## Dependencies

- Private XPC service contract
- Codex process manager
- Tool allowlist implementation
- Workspace and library path resolver
- Approval coordinator in the app shell

## Testing Implications

- Golden protocol tests for envelope validation and translation
- Integration tests using a fake Codex stdio process
- Ordering tests for deltas, approvals, tool starts, tool results, and terminal events
- Recovery tests for interruption, restart, and unrecoverable crash
- Negative tests for invalid envelope shapes and unauthorized tool names

## Open Issues

- Whether any provider-specific sideband events need dedicated app-facing types
- Whether tool output previews should be streamed as deltas or emitted as a completed artifact event
- Whether the resume-session contract persists child-process context or rebuilds it from serialized transcript state

## Acceptance Criteria

- The app-facing runtime interface can be expressed as stable Swift types.
- The XPC envelope contract covers every required user-visible runtime event.
- Protocol translation fails closed on unexpected payloads.
- Approval semantics, tool visibility, and terminal states are explicit and testable.
