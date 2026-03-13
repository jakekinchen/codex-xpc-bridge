import Foundation
import CodexBridgeContract

private struct ToolStep: Sendable {
    let invocationId: String
    let toolName: ToolName
    let summary: String
    let requiresApproval: Bool
    let arguments: [String: JSONValue]
}

private struct PendingTurn: Sendable {
    let prompt: String
    var queue: [ToolStep]
}

private actor CodexEngine {
    private var activeSessions: Set<String> = []
    private var pendingTurns: [String: PendingTurn] = [:]

    func handle(_ request: RuntimeRequestEnvelope) async throws {
        switch request.kind {
        case .createSession:
            activeSessions.insert(request.sessionId)
            try emit(.sessionReady, sessionId: request.sessionId, payload: CompletionPayload(finalText: "Session ready"))
            try emit(.providerStatus, sessionId: request.sessionId, payload: RuntimeStatusPayload(state: .ready, detail: "bundled-codex"))
        case .sendPrompt:
            let payload = try request.decodePayload(PromptSubmission.self)
            try await stream("Planning bounded workflow for: \(payload.prompt)", sessionId: request.sessionId)
            pendingTurns[request.sessionId] = buildPlan(for: payload.prompt)
            try dispatchNextToolOrComplete(sessionId: request.sessionId)
        case .toolResult:
            let payload = try request.decodePayload(ToolResultPayload.self)
            try await handleToolResult(payload, sessionId: request.sessionId)
        case .cancelOperation:
            pendingTurns.removeValue(forKey: request.sessionId)
            try emit(.runtimeWarning, sessionId: request.sessionId, payload: RuntimeErrorPayload(code: "cancelled", message: "Cancelled.", retryable: true))
            try emit(.assistantMessageCompleted, sessionId: request.sessionId, payload: CompletionPayload(finalText: "Cancelled."))
            try emit(.runtimeStatus, sessionId: request.sessionId, payload: RuntimeStatusPayload(state: .ready, detail: "cancelled"))
        case .terminateSession:
            pendingTurns.removeValue(forKey: request.sessionId)
            activeSessions.remove(request.sessionId)
            try emit(.sessionEnded, sessionId: request.sessionId, payload: SessionEndedPayload(reason: "terminated"))
        case .queryRuntimeStatus, .ping:
            try emit(.runtimeStatus, sessionId: request.sessionId, payload: RuntimeStatusPayload(state: status(for: request.sessionId), detail: "bundled-codex"))
        case .resolveApproval:
            break
        }
    }

    private func buildPlan(for prompt: String) -> PendingTurn {
        let lowercase = prompt.lowercased()
        let includeLibrarySave = lowercase.contains("full") || lowercase.contains("library") || lowercase.contains("save")
        var queue = [
            ToolStep(
                invocationId: "write-1",
                toolName: .writeWorkspaceFile,
                summary: "Write shader draft",
                requiresApproval: false,
                arguments: [
                    "path": .string("drafts/demo-input.glsl"),
                    "content": .string("void main() { gl_FragColor = vec4(1.0); }"),
                ]
            ),
            ToolStep(
                invocationId: "convert-1",
                toolName: .convertShader,
                summary: "Convert shader to WGSL",
                requiresApproval: true,
                arguments: [
                    "sourcePath": .string("drafts/demo-input.glsl"),
                    "targetPath": .string("drafts/demo-output.wgsl"),
                ]
            ),
            ToolStep(
                invocationId: "validate-1",
                toolName: .validateShader,
                summary: "Validate WGSL",
                requiresApproval: false,
                arguments: [
                    "sourcePath": .string("drafts/demo-output.wgsl"),
                ]
            ),
            ToolStep(
                invocationId: "preview-1",
                toolName: .capturePreview,
                summary: "Capture preview",
                requiresApproval: false,
                arguments: [
                    "name": .string("demo-preview"),
                ]
            ),
        ]

        if includeLibrarySave {
            queue.append(
                ToolStep(
                    invocationId: "save-1",
                    toolName: .saveToLibrary,
                    summary: "Save to library",
                    requiresApproval: true,
                    arguments: [
                        "sourcePath": .string("drafts/demo-output.wgsl"),
                        "name": .string("demo-output.wgsl"),
                    ]
                )
            )
        }

        return PendingTurn(prompt: prompt, queue: queue)
    }

    private func handleToolResult(_ result: ToolResultPayload, sessionId: String) async throws {
        guard pendingTurns[sessionId] != nil else { return }

        if result.success {
            try await stream(result.summary, sessionId: sessionId)
            try dispatchNextToolOrComplete(sessionId: sessionId)
            return
        }

        pendingTurns.removeValue(forKey: sessionId)
        try emit(.assistantMessageCompleted, sessionId: sessionId, payload: CompletionPayload(finalText: "Flow stopped after rejected or failed tool."))
        try emit(.runtimeStatus, sessionId: sessionId, payload: RuntimeStatusPayload(state: .ready, detail: "bundled-codex-idle"))
    }

    private func dispatchNextToolOrComplete(sessionId: String) throws {
        guard var turn = pendingTurns[sessionId] else { return }

        guard !turn.queue.isEmpty else {
            pendingTurns.removeValue(forKey: sessionId)
            try emit(.assistantMessageCompleted, sessionId: sessionId, payload: CompletionPayload(finalText: "Completed bounded pipeline."))
            try emit(.runtimeStatus, sessionId: sessionId, payload: RuntimeStatusPayload(state: .ready, detail: "bundled-codex-idle"))
            return
        }

        let next = turn.queue.removeFirst()
        pendingTurns[sessionId] = turn
        try emit(
            .toolCallRequested,
            sessionId: sessionId,
            payload: ToolCallPayload(
                toolInvocationId: next.invocationId,
                toolName: next.toolName,
                summary: next.summary,
                requiresApproval: next.requiresApproval,
                arguments: next.arguments
            )
        )
    }

    private func status(for sessionId: String) -> RuntimeStatusState {
        if pendingTurns[sessionId] != nil {
            return .busy
        }
        if activeSessions.contains(sessionId) {
            return .ready
        }
        return .disconnected
    }

    private func emit<P: Encodable>(_ kind: RuntimeEventKind, sessionId: String, payload: P) throws {
        let event = try RuntimeEventEnvelope.make(sessionId: sessionId, kind: kind, payload: payload)
        FileHandle.standardOutput.write(try JSONLineCodec.encode(event))
    }

    private func stream(_ message: String, sessionId: String) async throws {
        try emit(.assistantDelta, sessionId: sessionId, payload: AssistantDeltaPayload(text: "\(message) "))
        try await Task.sleep(for: .milliseconds(10))
    }
}

@main
private struct CodexRuntimeMain {
    static func main() async {
        let engine = CodexEngine()

        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                guard !line.isEmpty else { continue }
                let request = try JSONLineCodec.decode(RuntimeRequestEnvelope.self, from: Data(line.utf8))
                try await engine.handle(request)
            }
        } catch {
            fputs("codex runtime failure: \(error.localizedDescription)\n", stderr)
        }
    }
}
