# MAS XPC to Codex Stdio Architecture

Date: 2026-03-12
Status: Proposed v1 architecture
Owner: Runtime Platform

## Objective

Ship a Mac App Store-safe assistant runtime path with this fixed topology:

`SwiftUI app shell -> bundled private XPC service -> bundled native Codex binary over stdio`

The design preserves bounded assistant behavior while removing the legacy assumptions that are not acceptable for MAS v1:

- no bundled Node runtime
- no `localhost` transport
- no generic helper daemon topology
- no arbitrary shell execution
- no post-review code download

## Why XPC instead of direct app to Codex stdio

Direct app-to-stdio is simpler, but it pushes process supervision, stream parsing, restart logic, and trust boundaries into the UI process. XPC is the better long-term MAS seam because it:

- keeps the app shell isolated from parser and child-process failure modes
- provides a reviewable private helper boundary that Apple explicitly documents for macOS apps
- lets the service own entitlement-aware file access and container path mediation
- gives the app a typed RPC surface instead of raw subprocess management
- makes crash recovery and launch-on-demand behavior explicit

Decision:

- v1 ship target: `app -> XPC -> Codex stdio`
- rejected for v1: direct app -> Codex stdio in the main app process

Apple sources:

- App Sandbox overview: <https://developer.apple.com/documentation/security/app-sandbox>
- Creating XPC Services: <https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html>

## Component responsibilities

## App shell responsibilities

- render transcript, tool-call state, approvals, errors, and provider status
- initiate and close assistant sessions through typed XPC methods
- present user file pickers and capture security-scoped bookmarks where needed
- persist UI-facing conversation metadata that belongs to the app domain
- display approval requests and send `approve` or `reject` back to the XPC service
- avoid direct process spawning and avoid direct file-system writes outside approved seams

## XPC service responsibilities

- accept typed app requests over a private NSXPC interface
- launch and supervise the bundled Codex process on demand
- own stdin, stdout, and stderr pipes for Codex
- parse and emit the runtime envelope used between Swift and Codex
- enforce session ownership and map app requests to a single live Codex child per active session
- own tool execution approval gating
- run or broker bounded tools that are app-owned and allowlisted
- resolve container paths and verify all file access stays within the app container or active security-scoped grants
- translate child-process crashes, invalid payloads, and timeouts into app-facing error events
- write operational logs and diagnostic traces into the container

## Codex binary responsibilities

- maintain model/provider protocol behavior and prompt execution
- speak the approved stdio event protocol only
- request tools through typed tool-call events
- never discover tools dynamically
- never execute arbitrary shell commands in MAS mode
- treat `CODEX_HOME` and workspace roots as supplied by the service, not self-selected

## Process lifecycle

## Launch policy

- The XPC service launches on demand when the app creates its first assistant session.
- The service launches the bundled Codex binary lazily on first `startSession`.
- One warm Codex process is allowed per foreground user session in v1.
- The service may tear down the child process after an idle timeout, explicit session close, or app termination.

Recommended defaults:

- service startup timeout: 3 seconds
- Codex process startup timeout: 5 seconds
- idle tear-down timeout: 90 seconds

## Child process contract

- executable path is fixed to a bundled binary inside the app package or the XPC service resources
- environment is constructed exclusively by the XPC service
- stdin/stdout carry structured protocol messages
- stderr is captured for diagnostics and redacted before surfacing to UI
- no user-provided executable path is ever accepted

## Restart behavior

- If Codex exits unexpectedly while a session is active, the service emits `runtimeInterrupted`.
- The service may perform one automatic restart attempt for crash-class failures that are clearly recoverable.
- After a successful restart, the service emits `runtimeReconnected` and requires the app to recreate the logical session.
- Tool approvals do not survive a crash. Pending approvals are invalidated and must be re-requested.
- More than one child crash within 60 seconds trips a circuit breaker and blocks further restarts until explicit user retry.

## Shutdown behavior

- App termination triggers `shutdown(reason: appExit)` on the service.
- The service closes stdin, waits briefly for child exit, and then terminates the process if needed.
- Unflushed diagnostic logs are persisted before final shutdown.

## Stdio framing and event model

## Framing

Use newline-delimited JSON envelopes over stdin/stdout for v1.

Required envelope fields:

- `version`
- `sessionId`
- `messageId`
- `type`
- `timestamp`
- `payload`

Allowed `type` values from app/XPC to Codex:

- `startSession`
- `sendPrompt`
- `cancelTurn`
- `approveToolCall`
- `rejectToolCall`
- `closeSession`
- `ping`

Allowed `type` values from Codex to XPC/app:

- `sessionStarted`
- `delta`
- `toolCallRequested`
- `toolCallProgress`
- `toolCallCompleted`
- `approvalRequested`
- `turnCompleted`
- `providerStatus`
- `warning`
- `error`
- `runtimeInterrupted`

Rules:

- all messages are ordered within a session
- `messageId` is unique per session
- partial payloads are not valid messages
- invalid JSON or unknown message types terminate the active session and produce an error event

## Session and thread ownership

- One XPC client connection may own multiple logical transcript threads, but v1 only permits one active executing turn at a time per session.
- Each app conversation maps to one `sessionId`.
- Thread state that must survive restarts is owned by the app shell or container persistence, not by volatile service memory.
- The service stores only minimal runtime session metadata needed to reconnect, deduplicate, and recover diagnostics.

## Cancellation policy

- `cancelTurn` is best-effort and must be idempotent.
- The service sends a cancel envelope to Codex and starts a cancellation grace timer.
- If Codex does not acknowledge within 2 seconds, the service may terminate the child process and surface a cancellation-complete event after restart.
- Tools in progress receive a cooperative cancellation token if the tool type supports it.
- Non-cancelable operations must report `cancellationDeferred`.

## Timeout policy

- prompt execution soft timeout: 60 seconds unless tool execution extends the turn
- tool default timeout: 30 seconds
- preview capture timeout: 10 seconds
- shader validation timeout: 15 seconds
- import file access timeout: 10 seconds

Timeouts are enforced by the XPC service, not by the UI.

## `CODEX_HOME`, workspace, and storage mapping

All mutable state lives in the app container.

Recommended layout:

```text
~/Library/Containers/dev.codexbridge.demo/Data/
  Application Support/CodexBridge/
    codex-home/
    runtime-workspaces/
    style-memory/
    logs/
    diagnostics/
    imports/
    library/
```

Environment set by the XPC service:

- `CODEX_HOME=<container>/Application Support/CodexBridge/codex-home`
- `CODEX_BRIDGE_WORKSPACE_ROOT=<container>/Application Support/CodexBridge/runtime-workspaces`
- `CODEX_BRIDGE_STYLE_MEMORY_ROOT=<container>/Application Support/CodexBridge/style-memory`
- `CODEX_BRIDGE_LIBRARY_ROOT=<container>/Application Support/CodexBridge/library`
- `CODEX_BRIDGE_IMPORTS_ROOT=<container>/Application Support/CodexBridge/imports`
- `CODEX_BRIDGE_MAS_MODE=1`
- `HOME=<sandbox-safe value>`

Rules:

- the child process never writes into the app bundle
- any imported external file is copied into a staged workspace location before processing
- long-lived access to user-selected external paths requires security-scoped bookmarks owned by the app shell and consumed by the service only when necessary

## Approvals and tool execution

Approval flow:

1. Codex emits `approvalRequested` with the tool name, normalized inputs, and a human-readable reason.
2. The XPC service verifies the tool is on the allowlist and converts inputs to app-safe paths.
3. The service emits an approval event to the app shell.
4. The app presents approve or reject UI.
5. The service executes or rejects the tool and sends the typed result back into Codex.

Rules:

- open-ended tools never reach the approval UI because they are rejected at the allowlist layer
- approvals expire after 60 seconds unless renewed by the UI
- the service records an approval audit event containing session ID, tool name, normalized inputs, and outcome

## Diagnostics and logging

The service writes structured diagnostics to the container:

- `logs/runtime-service.log`
- `logs/codex-stderr.log`
- `diagnostics/session-<id>.json`

Redaction rules:

- redact provider tokens and auth secrets
- redact absolute user paths outside the container when displayed in UI
- cap captured stderr per turn to prevent log explosion

## Security boundaries

- The allowlist is closed and versioned.
- No dynamic tool discovery.
- No arbitrary executable launch.
- No unrestricted directory traversal.
- No symlink escapes beyond approved roots.
- No `localhost` server dependency by default.
- No `com.apple.security.network.server` entitlement unless future evidence proves it is strictly required.

Related Apple sources:

- App Review Guidelines 2.4.5 and 2.5.2: <https://developer.apple.com/app-store/review/guidelines/>
- Configuring the macOS App Sandbox: <https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox/>
- App Sandbox entitlement reference: <https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html>

## What lives where

## SwiftUI app shell

- transcript UI
- provider badges and readiness state
- file import UI
- approval UI
- app-owned persistence for user-visible metadata
- reconnect and recovery affordances

## XPC service

- session manager
- process supervisor
- stdio codec
- allowlist enforcement
- approval gating
- container path policy
- logging and diagnostics
- typed event translation

## Codex binary

- provider protocol logic
- prompt execution
- reasoning loop
- tool intent emission through typed requests only

## Assumptions needing validation

- the bundled native Codex binary supports the required provider modes without a localhost callback server
- the current app-server semantics can be represented cleanly as newline-delimited JSON over stdio
- the XPC service can inherit or obtain the required sandbox entitlements for container and security-scoped file access
- the WGSL conversion and validation path can run entirely within the bounded MAS tool model

## v1 required scope

- assistant transcript streaming
- approval flow
- bounded shader tool surface
- container-scoped persistence
- crash detection and one-shot restart
- packaging and release gates that prove the legacy Node or localhost topology is absent

## Follow-up scope

- multi-session warm pooling
- richer provider fallback matrix
- analytics and telemetry aggregation
- broader non-WGSL tool surface
- native replacement for any remaining bundled conversion utilities
