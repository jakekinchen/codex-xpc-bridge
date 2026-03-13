# MAS App Review Notes: Bounded Tool Model

Last updated: 2026-03-12
Status: Draft reviewer guidance
Owner: Release engineering / PM

## Reviewer-facing summary

This app includes an assistant workflow for bounded shader and workspace tasks. In the Mac App Store build, the assistant does not expose a general terminal, shell, plugin host, or arbitrary code execution surface.

The MAS runtime path is implemented as:

- the app UI
- a private XPC service bundled inside the app
- a bundled native assistant binary launched by that service over stdio

The bundled service exists only to isolate and manage the runtime process. It is not a user-facing automation endpoint.

## What the assistant is allowed to do

The shipped assistant can perform only an app-defined allowlist of document-processing tasks, such as:

- importing a user-selected shader file into the app workspace
- converting supported source material into WGSL or another bounded internal representation
- validating supported shader artifacts
- generating local previews
- saving style profiles
- reading and writing workspace files inside the app container
- saving generated artifacts into the app library

## What the assistant is not allowed to do

The MAS build does not provide:

- generic shell access
- arbitrary local command execution
- execution of user-provided binaries
- dynamic plugin installation
- open-ended tool discovery
- localhost server transport for the assistant runtime

## File and data boundaries

- Generated data, style memory, and library assets are stored as user data in the app container.
- When the user selects files from outside the container, the app uses standard user-granted file access and imports those files into the workspace before processing.
- The assistant does not receive unrestricted access to the file system.

## Why this design is used

Apple's sandbox and XPC guidance supports private bundled helper/service patterns for app-internal functionality, while the App Review Guidelines require apps to remain self-contained and safe for users. This design keeps the runtime bounded, typed, and reviewable.

Primary sources:

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Sandbox overview](https://developer.apple.com/documentation/security/app-sandbox)
- [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox/)
- [Enabling App Sandbox](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)
- [Creating XPC Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)

## Internal reviewer-prep notes

- Do not describe the feature as a general-purpose coding or terminal environment in the MAS submission.
- Do not claim support for providers or auth modes that have not been validated in the bundled native path.
- If the MAS build ships a narrower provider set or narrower conversion scope than non-MAS builds, disclose that accurately.
- If App Review asks why localhost is absent, the answer is that the MAS build uses a private in-bundle XPC service and stdio instead of an app-hosted server.
