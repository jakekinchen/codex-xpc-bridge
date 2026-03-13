# MAS Risk Register

Last updated: 2026-03-12
Status: Active
Owner: Runtime PM

## Scoring

- Severity: High, Medium, Low
- Deadline: latest point by which the decision or mitigation must be locked to avoid schedule slip

| ID | Risk | Severity | Why it matters | Mitigation | Missing evidence | Owner | Decision deadline |
| --- | --- | --- | --- | --- | --- | --- | --- |
| R1 | Native Codex login path may rely on browser or localhost callback behavior that is not MAS-safe. | High | Unsupported auth breaks provider availability and parity claims. | Treat auth as untrusted until exercised in the bundled native path; gate supported provider modes behind proof. | Real login trace and entitlement review. | Provider integration lead | Before Packet C exit |
| R2 | Some current conversion or validation logic may still assume shell scripts or external toolchains. | High | MAS cannot depend on open-ended shell execution or post-review downloads. | Inventory each conversion/validation dependency and wrap only reviewed bundled components. Narrow v1 to WGSL-first if needed. | Dependency list and bundle audit. | Conversion pipeline owner | Before Packet E start |
| R3 | Child-process sandbox inheritance or entitlement interaction may be misunderstood. | High | Wrong assumptions can cause review rejection or runtime failure. | Verify signing, entitlement inheritance, and runtime behavior with packaging tests and a notarized-style bundle inspection. | Signed fixture results. | macOS platform owner | Before Packet G sign-off |
| R4 | Approval recovery after XPC interruption may lose request context. | Medium | User trust degrades if approvals are replayed incorrectly or lost silently. | Persist only minimal approval context in the app shell and require explicit replay semantics. | Interrupt/reconnect integration tests. | App shell owner | Before Packet F exit |
| R5 | Restart behavior after Codex crash may create transcript desync. | Medium | Users could see hanging sessions or duplicated events. | Make session recreation explicit and append system events for crash/restart transitions. | Fake-Codex crash traces. | XPC/runtime owner | Before Packet F exit |
| R6 | Container workspace confinement may be bypassed by symlink or alias traversal. | High | Security boundary failure is both a product and review problem. | Canonicalize all paths and reject any post-resolution target outside the workspace root. | Security regression tests. | Workspace service owner | Before Packet D exit |
| R7 | MAS v1 parity may be overstated relative to the actually supported provider/tool surface. | High | Misstated parity creates product debt and App Review risk. | Lock a bounded parity matrix and require launch copy to match it exactly. | PM-reviewed parity scorecard. | Product + PM | Before launch copy freeze |
| R8 | Preview capture or rendering may require capabilities not available in the XPC or child-process lane. | Medium | Missing preview harms the core shader workflow. | Keep rendering in the app-owned subsystem if sandbox or GPU constraints make service-side rendering fragile. | Design spike and E2E proof. | Rendering owner | Before Packet E exit |
| R9 | Logging may capture sensitive prompts, file paths, or provider metadata in review artifacts. | Medium | Sensitive logging increases privacy and review risk. | Define redaction rules and separate debug-only traces from release evidence. | Logging policy doc and test coverage. | Runtime owner | Before Packet F exit |
| R10 | The release gate may fail to catch forbidden legacy payloads. | Medium | A bundle can pass local QA but still ship review-hostile components. | Make the readiness script assert forbidden payload absence and required nested-bundle presence. | Script coverage and sample bundle checks. | Release engineering | Before Packet G exit |

## Watchlist assumptions

- WGSL-first scope is sufficient for MAS v1 unless conversion dependency review disproves it.
- `network.server` is not required for the bounded runtime path unless auth or provider behavior proves otherwise.
- The XPC service remains private and app-bundled, not a user-exposed automation surface.
- Style memory and library content are user data and must never be treated as mutable bundle resources.

## Escalation rules

- Any discovery that reintroduces Node, localhost, generic shell, or arbitrary executable launch is launch-blocking.
- Any provider requirement that cannot be reconciled with MAS-safe auth must be scoped out explicitly rather than deferred silently.
- Any failure to prove workspace confinement is a security stop, not a follow-up task.
