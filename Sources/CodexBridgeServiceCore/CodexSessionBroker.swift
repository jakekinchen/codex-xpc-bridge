import Foundation
import CodexBridgeContract
import CodexBridgeSupport
import CodexBridgeXPC

public actor CodexSessionBroker {
    public typealias EventSink = @Sendable (RuntimeEventEnvelope) -> Void

    private let pathResolver: RuntimePathResolver
    private let diagnostics: DiagnosticsRecorder
    private let binaryLocator: RuntimeBinaryLocator
    private let eventSink: EventSink
    private var sessions: [String: CodexSession] = [:]

    public init(
        pathResolver: RuntimePathResolver = RuntimePathResolver(),
        binaryLocator: RuntimeBinaryLocator = RuntimeBinaryLocator(),
        eventSink: @escaping EventSink
    ) throws {
        self.pathResolver = pathResolver
        let paths = try pathResolver.ensureBaseDirectories()
        self.diagnostics = DiagnosticsRecorder(logsRoot: paths.logsRoot)
        self.binaryLocator = binaryLocator
        self.eventSink = eventSink
    }

    public func handle(_ request: RuntimeRequestEnvelope) async throws -> RuntimeReplyEnvelope {
        if request.kind == .createSession {
            return try await startSession(request)
        }

        let session = try await session(for: request.sessionId)
        switch request.kind {
        case .sendPrompt:
            try await session.sendPrompt(request)
            return ack(for: request, detail: "Prompt sent")
        case .resolveApproval:
            try await session.resolveApproval(request)
            return ack(for: request, detail: "Approval resolved")
        case .cancelOperation:
            try await session.cancel(request)
            return ack(for: request, detail: "Cancellation forwarded")
        case .terminateSession:
            await session.stop(reason: "terminated by client")
            sessions.removeValue(forKey: request.sessionId)
            return ack(for: request, detail: "Session terminated")
        case .queryRuntimeStatus:
            let status = await session.currentStatus()
            return RuntimeReplyEnvelope(
                requestId: request.requestId,
                accepted: true,
                message: "Runtime status",
                payload: try PayloadCoder.encode(RuntimeStatusPayload(state: status, detail: nil))
            )
        case .toolResult, .ping:
            return ack(for: request, detail: "Ignored at broker boundary")
        case .createSession:
            return try await startSession(request)
        }
    }

    public func closeSession(_ sessionId: String) async {
        guard let session = sessions.removeValue(forKey: sessionId) else { return }
        await session.stop(reason: "closed")
    }

    public func shutdown() async {
        let active = sessions.values
        sessions.removeAll()
        for session in active {
            await session.stop(reason: "service shutdown")
        }
    }

    private func startSession(_ request: RuntimeRequestEnvelope) async throws -> RuntimeReplyEnvelope {
        let session = try await session(for: request.sessionId)
        try await session.startIfNeeded(createPayload: (try? request.decodePayload(SessionCreatePayload.self)) ?? SessionCreatePayload())
        return ack(for: request, detail: "Session ready")
    }

    private func session(for sessionId: String) async throws -> CodexSession {
        if let session = sessions[sessionId] {
            return session
        }

        let paths = try pathResolver.ensureBaseDirectories()
        let session = CodexSession(
            sessionId: sessionId,
            pathResolver: pathResolver,
            paths: paths,
            binaryLocator: binaryLocator,
            diagnostics: diagnostics,
            eventSink: eventSink
        )
        sessions[sessionId] = session
        return session
    }

    private func ack(for request: RuntimeRequestEnvelope, detail: String) -> RuntimeReplyEnvelope {
        RuntimeReplyEnvelope(
            requestId: request.requestId,
            accepted: true,
            message: detail,
            payload: try? PayloadCoder.encode(AckPayload(acceptedKind: request.kind.rawValue, detail: detail))
        )
    }
}

actor CodexSession {
    private let sessionId: String
    private let pathResolver: RuntimePathResolver
    private let paths: RuntimePaths
    private let binaryLocator: RuntimeBinaryLocator
    private let diagnostics: DiagnosticsRecorder
    private let eventSink: @Sendable (RuntimeEventEnvelope) -> Void

    private var processManager: CodexProcessManager?
    private var pendingApprovals: [String: ToolCallPayload] = [:]
    private var status: RuntimeStatusState = .starting
    private var restartAttempts = 0
    private var createPayload = SessionCreatePayload()
    private lazy var toolExecutor = CodexToolExecutor(paths: paths, resolver: pathResolver)

    init(
        sessionId: String,
        pathResolver: RuntimePathResolver,
        paths: RuntimePaths,
        binaryLocator: RuntimeBinaryLocator,
        diagnostics: DiagnosticsRecorder,
        eventSink: @escaping @Sendable (RuntimeEventEnvelope) -> Void
    ) {
        self.sessionId = sessionId
        self.pathResolver = pathResolver
        self.paths = paths
        self.binaryLocator = binaryLocator
        self.diagnostics = diagnostics
        self.eventSink = eventSink
    }

    func startIfNeeded(createPayload: SessionCreatePayload) async throws {
        self.createPayload = createPayload
        guard processManager == nil else { return }

        let binaryURL = try binaryLocator.locate()
        let environment = try pathResolver.genericEnvironment().merging([
            "CODEX_BRIDGE_SESSION_ID": sessionId,
            "CODEX_BRIDGE_WORKSPACE": try pathResolver.workspaceURL(sessionID: sessionId).path,
        ]) { _, newValue in newValue }

        let manager = CodexProcessManager(
            binaryURL: binaryURL,
            environment: environment,
            diagnostics: diagnostics,
            eventHandler: { [weak self] event in
                await self?.handleRuntimeEvent(event)
            },
            terminationHandler: { [weak self] reason in
                await self?.handleRuntimeTermination(reason: reason)
            }
        )
        try await manager.start()
        processManager = manager
        status = .starting

        let createRequest = RuntimeRequestEnvelope(
            sessionId: sessionId,
            kind: .createSession,
            payload: try PayloadCoder.encode(createPayload)
        )
        try await manager.send(createRequest)
    }

    func sendPrompt(_ request: RuntimeRequestEnvelope) async throws {
        try await startIfNeeded(createPayload: createPayload)
        status = .busy
        if let processManager {
            try await processManager.send(request)
        }
    }

    func resolveApproval(_ request: RuntimeRequestEnvelope) async throws {
        let resolution = try request.decodePayload(ApprovalResolutionPayload.self)
        guard let toolCall = pendingApprovals.removeValue(forKey: resolution.toolInvocationId) else {
            throw XPCErrorFactory.message("No pending approval for \(resolution.toolInvocationId)")
        }

        let approvalResolved = RuntimeEventEnvelope(
            sessionId: sessionId,
            kind: .approvalResolved,
            payload: try PayloadCoder.encode(
                ApprovalResolvedPayload(
                    toolInvocationId: toolCall.toolInvocationId,
                    toolName: toolCall.toolName,
                    decision: resolution.decision
                )
            )
        )
        eventSink(approvalResolved)

        if resolution.decision == .reject {
            let result = ToolResultPayload(toolInvocationId: toolCall.toolInvocationId, toolName: toolCall.toolName, success: false, summary: "User rejected \(toolCall.toolName.rawValue).")
            eventSink(RuntimeEventEnvelope(sessionId: sessionId, kind: .toolCallFailed, payload: try PayloadCoder.encode(result)))
            if let processManager {
                try await processManager.send(RuntimeRequestEnvelope(sessionId: sessionId, kind: .toolResult, payload: try PayloadCoder.encode(result)))
            }
            status = .ready
            return
        }

        try await executeTool(toolCall)
    }

    func cancel(_ request: RuntimeRequestEnvelope) async throws {
        status = .ready
        if let processManager {
            try await processManager.send(request)
        }
    }

    func currentStatus() -> RuntimeStatusState {
        status
    }

    func stop(reason: String) async {
        pendingApprovals.removeAll()
        status = .stopped
        await processManager?.stop(reason: reason)
        processManager = nil
        let ended = RuntimeEventEnvelope(sessionId: sessionId, kind: .sessionEnded, payload: try? PayloadCoder.encode(SessionEndedPayload(reason: reason)))
        eventSink(ended)
    }

    private func handleRuntimeEvent(_ event: RuntimeEventEnvelope) async {
        switch event.kind {
        case .toolCallRequested:
            await handleToolRequest(event)
        case .assistantMessageCompleted:
            status = .ready
            eventSink(event)
        case .runtimeError:
            status = .interrupted
            eventSink(event)
        case .providerStatus, .runtimeStatus:
            if let payload = try? event.decodePayload(RuntimeStatusPayload.self) {
                status = payload.state
            }
            eventSink(event)
        default:
            eventSink(event)
        }
    }

    private func handleRuntimeTermination(reason: String) async {
        guard reason != "stopped" else { return }
        eventSink(RuntimeEventEnvelope(sessionId: sessionId, kind: .serviceInterrupted, payload: try? PayloadCoder.encode(RuntimeErrorPayload(code: "runtime_interrupted", message: reason, retryable: true))))

        guard restartAttempts < 1 else {
            status = .interrupted
            eventSink(RuntimeEventEnvelope(sessionId: sessionId, kind: .runtimeError, payload: try? PayloadCoder.encode(RuntimeErrorPayload(code: "runtime_crash", message: "Runtime exited unexpectedly.", retryable: true))))
            return
        }

        restartAttempts += 1
        processManager = nil
        do {
            try await startIfNeeded(createPayload: createPayload)
            status = .ready
            eventSink(RuntimeEventEnvelope(sessionId: sessionId, kind: .serviceRecovered, payload: try? PayloadCoder.encode(RuntimeStatusPayload(state: .ready, detail: "Runtime restarted"))))
        } catch {
            status = .interrupted
            eventSink(RuntimeEventEnvelope(sessionId: sessionId, kind: .runtimeError, payload: try? PayloadCoder.encode(RuntimeErrorPayload(code: "restart_failed", message: error.localizedDescription, retryable: false))))
        }
    }

    private func handleToolRequest(_ event: RuntimeEventEnvelope) async {
        guard let toolCall = try? event.decodePayload(ToolCallPayload.self) else {
            eventSink(event)
            return
        }

        eventSink(event)
        if toolCall.requiresApproval {
            pendingApprovals[toolCall.toolInvocationId] = toolCall
            let approval = RuntimeEventEnvelope(
                sessionId: sessionId,
                kind: .approvalRequired,
                payload: try? PayloadCoder.encode(ApprovalRequiredPayload(toolInvocationId: toolCall.toolInvocationId, toolName: toolCall.toolName, reason: "This tool mutates user-visible artifacts.", inputSummary: toolCall.summary))
            )
            eventSink(approval)
            status = .waitingForApproval
            return
        }

        do {
            try await executeTool(toolCall)
        } catch {
            eventSink(RuntimeEventEnvelope(sessionId: sessionId, kind: .toolCallFailed, payload: try? PayloadCoder.encode(RuntimeErrorPayload(code: "tool_failed", message: error.localizedDescription, retryable: true))))
        }
    }

    private func executeTool(_ toolCall: ToolCallPayload) async throws {
        eventSink(RuntimeEventEnvelope(sessionId: sessionId, kind: .toolCallStarted, payload: try PayloadCoder.encode(toolCall)))
        let result = try await toolExecutor.execute(toolCall: toolCall, sessionID: sessionId)
        eventSink(RuntimeEventEnvelope(sessionId: sessionId, kind: result.success ? .toolCallCompleted : .toolCallFailed, payload: try PayloadCoder.encode(result)))
        if let processManager {
            try await processManager.send(RuntimeRequestEnvelope(sessionId: sessionId, kind: .toolResult, payload: try PayloadCoder.encode(result)))
        }
    }
}
