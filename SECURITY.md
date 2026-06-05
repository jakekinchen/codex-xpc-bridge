# Security Policy

`CodexXPCBridge` is a reference implementation for brokering a bundled Codex-style runtime through a macOS app and private XPC service. Please treat security reports seriously even when they affect only the demo configuration.

## Supported versions

The `main` branch is the supported development line until the project cuts stable releases.

## Reporting a vulnerability

Please open a private security advisory on GitHub if the report involves:

- path traversal or workspace confinement bypasses
- tool execution that skips required approval
- runtime protocol injection or malformed-message handling bugs
- App/XPC/service boundary issues
- packaging behavior that exposes the bundled runtime unexpectedly

If GitHub private advisories are unavailable, email the maintainer listed on the GitHub profile with a concise report and reproduction steps.

## Security model

The default demo is intentionally conservative:

- unknown tools require approval by default
- path resolution rejects absolute paths and traversal outside the workspace root
- runtime startup and approval waits have bounded timeouts
- malformed runtime stdout causes a protocol-violation interruption
- host apps are expected to inject their own approval policy and tool executor

This project does not claim that a host app is App Store-ready or secure by adopting the bridge unchanged. Treat it as a tested boundary and adapt the policy, entitlements, signing, and runtime packaging to your app.
