# MAS Parity Matrix

Last updated: 2026-03-12
Status: Draft bounded-surface parity contract
Owner: Runtime PM / macOS platform

## Purpose

This matrix defines which current assistant behaviors must match the external runtime, which may diverge acceptably in MAS, and which are intentionally unsupported.

## Classification key

- `must-match`: required for MAS v1 ship readiness.
- `acceptable-divergence`: allowed difference if documented and not user-hostile.
- `unsupported`: intentionally omitted from MAS.

## Matrix

| Parity item | Classification | MAS expectation | Notes |
| --- | --- | --- | --- |
| Assistant transcript streaming | must-match | Token and event streaming remain visible in-session. | Transport changes, user-visible behavior should not. |
| Tool-call visibility | must-match | UI shows which bounded tool ran and why. | Tool name may be normalized for MAS clarity. |
| Tool-result visibility | must-match | Result summary and produced artifacts are visible. | Artifact links must remain container-safe. |
| Approval-required flow | must-match | Tool requests needing approval surface explicit approve/reject UI. | Approval is tied to typed payloads, not raw commands. |
| Approval approve/reject behavior | must-match | Approve executes the exact request; reject sends deterministic failure back to the session. | No hidden fallback execution. |
| Draft preview generation | must-match | Supported bounded draft flows still yield previews. | Preview quality may vary by implementation path. |
| Save/apply completion | must-match | User can persist accepted outputs without leaving the MAS path. | Applies to container or explicitly granted destinations only. |
| Provider status rendering | must-match | UI exposes connected, unavailable, auth-blocked, and degraded states. | Exact iconography may differ. |
| Workspace file persistence | must-match | Session artifacts survive relaunch inside the container workspace. | Persistence location changes from legacy topology. |
| User style memory loading | must-match | Saved style memory loads into later sessions. | Container-scoped storage only. |
| User style memory saving | must-match | Saving style memory remains possible. | Schema/versioning may tighten in MAS. |
| Shader conversion | must-match | Supported WGSL-first conversions remain available. | Scope may narrow to explicitly supported formats. |
| Shader validation | must-match | Validation results remain available before save/apply. | Internal implementation may replace shell-based path. |
| Preview capture | must-match | Preview images or equivalent artifacts remain available. | Output location is container-managed. |
| Library save behavior | must-match | Final artifacts can be saved to the app library. | Library becomes canonical MAS persistence target. |
| Error reporting | must-match | Errors remain visible with actionable next step. | MAS-specific policy failures need explicit wording. |
| Crash/reconnect behavior | must-match | Child-process crash or service interruption yields visible recovery behavior. | Recovery may recreate session rather than transparently resume. |
| Session warm reuse | acceptable-divergence | MAS may relaunch Codex on demand instead of keeping a long-lived warm daemon. | User impact must remain low. |
| Startup latency | acceptable-divergence | Small latency increase is acceptable on first request. | Must remain within product budget. |
| Auth flow | acceptable-divergence | MAS may support fewer provider auth modes initially. | Any limitation must be disclosed. |
| Provider set breadth | acceptable-divergence | MAS v1 may ship only provider modes proven review-safe. | Keep parity for the supported subset. |
| Arbitrary shell tools | unsupported | No generic command execution in MAS. | Replaced by explicit allowlist. |
| Arbitrary local helper plugins | unsupported | No open-ended helper/plugin model. | Review-hostile and out of scope. |
| Localhost transport semantics | unsupported | No HTTP/WS localhost runtime seam in MAS. | XPC + stdio replaces it. |
| User-provided executable paths | unsupported | No execution of binaries outside the app bundle. | Hard policy boundary. |
| Dynamic tool discovery | unsupported | Tool set is static and app-shipped. | Changes require app update. |

## v1 parity scorecard rules

- Ship gate requires all `must-match` items to be green or have an explicitly approved launch-blocker waiver.
- `acceptable-divergence` items require documented rationale, UX wording if visible, and PM sign-off.
- `unsupported` items require clear messaging so MAS does not imply parity it does not actually provide.

## Evidence expectations

Each `must-match` row needs at least one of the following before release:

- automated test evidence
- smoke-suite trace
- packaging proof
- UI capture demonstrating visible behavior
- failure-mode capture demonstrating recovery behavior
