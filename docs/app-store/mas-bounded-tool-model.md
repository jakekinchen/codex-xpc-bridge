# MAS Bounded Tool Model

Last updated: 2026-03-12
Status: Draft v1 capability contract
Owner: Runtime / assistant platform

## Goal

Define the exact tool surface allowed in the Mac App Store runtime path. The model is closed by default. Any tool not listed here is unsupported in MAS.

## Policy basis

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Sandbox overview](https://developer.apple.com/documentation/security/app-sandbox)
- [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox/)
- [Enabling App Sandbox](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)

## Closed-world rules

- The app shell owns the tool registry.
- The XPC service brokers requests to the bundled Codex process but does not expose arbitrary execution.
- The Codex process can request only typed tool identifiers with declared payload schemas.
- Tool handlers run inside app-owned code paths or tightly controlled bundled helpers.
- Tools may read or write only container-scoped paths or currently granted user-selected files.
- No tool may spawn arbitrary executables, open a shell, traverse unrestricted paths, or start a server.

## v1 allowlist

### `import_shader`

- Purpose: Copy a user-selected source asset into the container workspace for assistant processing.
- Allowed inputs: security-scoped bookmark or currently active user selection token, declared import mode, supported file type metadata.
- Disallowed inputs: raw arbitrary filesystem paths, directory recursion requests, hidden-system paths, executable payloads.
- Persistence behavior: imported file is copied into a session or project workspace under the app container.
- Timeout expectation: under 5 seconds for ordinary source files.
- Failure modes: bookmark stale, permission denied, unsupported type, oversized asset, copy failure.
- Security constraints: resolve access only through explicit user grant; normalize and reject symlink escapes.
- Owner: app shell file-import layer with XPC-visible result envelope.

### `convert_shader`

- Purpose: Convert imported source material into WGSL or another explicitly supported intermediate representation for preview and save flows.
- Allowed inputs: workspace file identifiers, declared conversion mode, bounded conversion options.
- Disallowed inputs: arbitrary shell flags, user-specified executables, network fetches, uncontrolled include paths.
- Persistence behavior: writes results into the container workspace only.
- Timeout expectation: under 30 seconds for supported fixture sizes.
- Failure modes: unsupported source format, converter failure, timeout, malformed output.
- Security constraints: use bundled conversion implementation only; no dynamic dependency download.
- Owner: XPC service tool broker invoking app-owned conversion pipeline.

### `validate_shader`

- Purpose: Run bounded validation on a workspace shader artifact before preview or library save.
- Allowed inputs: workspace file identifier, validation profile, bounded flags defined by the app.
- Disallowed inputs: arbitrary CLI flags, arbitrary file reads, external toolchain resolution.
- Persistence behavior: validation report stored as ephemeral result or container-scoped artifact when needed for diagnostics.
- Timeout expectation: under 15 seconds for supported assets.
- Failure modes: parse error, probe failure, frame mismatch, timeout.
- Security constraints: validation logic must remain internalized or use bundled reviewed helpers only.
- Owner: app-owned validation service surfaced through the XPC runtime.

### `capture_preview`

- Purpose: Generate preview imagery for the current draft or converted shader.
- Allowed inputs: workspace artifact ID, bounded render parameters, target output format.
- Disallowed inputs: arbitrary rendering programs, external network assets, unrestricted render scripts.
- Persistence behavior: preview files stored in the container cache or workspace preview area.
- Timeout expectation: under 20 seconds.
- Failure modes: render failure, invalid asset, timeout, unsupported profile.
- Security constraints: preview generation is local-only and container-scoped.
- Owner: app rendering subsystem or bundled render helper behind typed RPC.

### `save_style_profile`

- Purpose: Persist user style memory or assistant-generated style preferences as app data.
- Allowed inputs: typed style profile payload, version, user-visible label.
- Disallowed inputs: executable content, arbitrary blobs, paths outside style-memory storage.
- Persistence behavior: writes to container-scoped user-data storage.
- Timeout expectation: under 2 seconds.
- Failure modes: serialization error, version mismatch, quota or write failure.
- Security constraints: treat style memory as user data, not bundle resources.
- Owner: app shell persistence layer.

### `save_to_library`

- Purpose: Persist final WGSL or related bounded artifacts to the user library managed by the app.
- Allowed inputs: workspace artifact ID, metadata, optional preview references.
- Disallowed inputs: raw out-of-container destinations unless explicitly user-selected and granted.
- Persistence behavior: writes to container-scoped library storage and updates library index.
- Timeout expectation: under 5 seconds.
- Failure modes: duplicate collision, write failure, metadata validation failure.
- Security constraints: no mutation of app-bundle resources; library assets are user data.
- Owner: app library service.

### `read_workspace_file`

- Purpose: Read bounded workspace artifacts needed for transcript context or downstream tools.
- Allowed inputs: workspace-relative identifiers, declared byte or line limits.
- Disallowed inputs: absolute arbitrary paths, parent-directory traversal, symlink escapes, directory listings outside bounded scope.
- Persistence behavior: read-only.
- Timeout expectation: under 2 seconds.
- Failure modes: missing file, confinement rejection, oversized request.
- Security constraints: resolve through a canonical workspace root and reject escape attempts.
- Owner: workspace service.

### `write_workspace_file`

- Purpose: Persist generated files needed for drafts, transforms, or user edits.
- Allowed inputs: workspace-relative identifiers, bounded text or binary payload, declared media type.
- Disallowed inputs: absolute paths, parent-directory traversal, executable placement, writes outside workspace root.
- Persistence behavior: writes only inside the container workspace.
- Timeout expectation: under 2 seconds.
- Failure modes: confinement rejection, write failure, invalid encoding.
- Security constraints: canonicalize target path and reject symlink or alias escapes.
- Owner: workspace service.

## Explicitly unsupported in MAS

- `exec`
- `shell`
- Generic `run_command`
- Arbitrary `open_url`
- Dynamic tool registration
- Arbitrary HTTP fetch for tool execution
- Arbitrary plugin install
- Execution of user-provided binaries

## Approval model

- Read-only workspace operations may auto-approve when the target remains inside the container workspace.
- Import operations require direct user selection or a valid stored bookmark.
- Mutating operations that affect user-visible outputs surface a typed approval card when policy requires it.
- Approvals are tied to the specific tool request payload and expire on session reset or reconnect.

## File and bookmark handling

- User-selected files are copied into the container workspace before conversion or validation.
- Persisted post-selection access requires security-scoped bookmarks; bookmark scope is the minimum necessary.
- The app shell, not the Codex child, owns bookmark resolution and hands the runtime only scoped container paths or ephemeral access tokens.
- No tool receives a raw unrestricted user path as an execution primitive.

## Event mapping back to UI

- Tool request -> approval card or immediate execution badge.
- Tool start -> transcript event with tool name and bounded target summary.
- Tool result -> transcript event with status, artifact references, and user-visible next actions.
- Tool failure -> transcript error block with retryability classification.

## Ownership boundaries

- Swift UI/app shell: approvals, file selection, bookmark ownership, workspace navigation, provider status, user-facing transcript.
- XPC service: session broker, Codex lifecycle, typed request/response forwarding, timeout and crash handling.
- Codex binary: assistant orchestration and bounded tool intent production only.
- App-owned services: workspace IO, library save, style memory, conversion, validation, preview generation.
