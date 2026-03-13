import Foundation
import CodexBridgeContract
import CodexBridgeSupport
import CodexBridgeXPC

public actor CodexSessionBroker {
    public typealias EventSink = @Sendable (RuntimeEventEnvelope) -> Void

    private let pathResolver: RuntimePathResolver
    private let diagnostics: DiagnosticsRecorder
    private let binaryLocator: RuntimeBinaryLocator
    private let toolHandlerFactory: ToolHandlingFactory
    private let approvalPolicy: any ToolApprovalPolicy
    private let restartPolicy: RestartPolicy
    private let timeoutPolicy: TimeoutPolicy
    private let eventSink: EventSink
    private var sessions: [String: CodexSession] = [:]

    public init(
        pathResolver: RuntimePathResolver = RuntimePathResolver(),
        binaryLocator: RuntimeBinaryLocator = RuntimeBinaryLocator(),
        approvalPolicy: any ToolApprovalPolicy = ApprovalPolicy(),
        restartPolicy: RestartPolicy = RestartPolicy(),
        timeoutPolicy: TimeoutPolicy = TimeoutPolicy(),
        toolHandlerFactory: @escaping ToolHandlingFactory = { paths, resolver in
            DemoToolExecutor(paths: paths, resolver: resolver)
        },
        eventSink: @escaping EventSink
    ) throws {
        self.pathResolver = pathResolver
        let paths = try pathResolver.ensureBaseDirectories()
        self.diagnostics = DiagnosticsRecorder(logsRoot: paths.logsRoot)
        self.binaryLocator = binaryLocator
        self.approvalPolicy = approvalPolicy
        self.restartPolicy = restartPolicy
        self.timeoutPolicy = timeoutPolicy
        self.toolHandlerFactory = toolHandlerFactory
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
            toolHandler: toolHandlerFactory(paths, pathResolver),
            approvalPolicy: approvalPolicy,
            restartPolicy: restartPolicy,
            timeoutPolicy: timeoutPolicy,
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

private struct RoutedToolCall: Sendable {
    let runtimeToolInvocationId: String
    let hostToolCall: ToolCallPayload

    var hostToolInvocationId: String { hostToolCall.toolInvocationId }
    var toolName: ToolID { hostToolCall.toolName }

    func approvalRequiredPayload(reason: String) -> ApprovalRequiredPayload {
        ApprovalRequiredPayload(
            toolInvocationId: hostToolInvocationId,
            toolName: toolName,
            reason: reason,
            inputSummary: hostToolCall.summary
        )
    }

    func approvalResolvedPayload(decision: ApprovalResolution) -> ApprovalResolvedPayload {
        ApprovalResolvedPayload(
            toolInvocationId: hostToolInvocationId,
            toolName: toolName,
            decision: decision
        )
    }

    func hostResult(success: Bool, summary: String) -> ToolResultPayload {
        ToolResultPayload(
            toolInvocationId: hostToolInvocationId,
            toolName: toolName,
            success: success,
            summary: summary
        )
    }

    func runtimeResult(from hostResult: ToolResultPayload) -> ToolResultPayload {
        ToolResultPayload(
            toolInvocationId: runtimeToolInvocationId,
            toolName: hostResult.toolName,
            success: hostResult.success,
            summary: hostResult.summary,
            outputs: hostResult.outputs,
            artifactPaths: hostResult.artifactPaths
        )
    }
}

private enum SessionTermination {
    static let ignoredReasons: Set<String> = [
        "stopped",
        "closed",
        "service shutdown",
        "terminated by client",
        "idle_timeout",
    ]

    static func payload(for reason: String) -> RuntimeErrorPayload? {
        switch reason {
        case "protocol_violation":
            return RuntimeErrorPayload(code: "protocol_violation", message: "Runtime emitted malformed or invalid stdout.", retryable: false)
        case "startup_timeout":
            return RuntimeErrorPayload(code: "startup_timeout", message: "Runtime startup timed out.", retryable: false)
        case "prompt_timeout":
            return RuntimeErrorPayload(code: "prompt_timeout", message: "Runtime did not make progress after prompt dispatch.", retryable: false)
        case "child_silence_timeout":
            return RuntimeErrorPayload(code: "child_silence_timeout", message: "Runtime stdout stalled.", retryable: false)
        default:
            return nil
        }
    }
}

private enum SessionToolExecutionError: LocalizedError {
    case timedOut(ToolID)

    var errorDescription: String? {
        switch self {
        case .timedOut(let toolID):
            return "Tool execution timed out for \(toolID.rawValue)."
        }
    }
}

actor CodexSession {
    private let sessionId: String
    private let pathResolver: RuntimePathResolver
    private let paths: RuntimePaths
    private let binaryLocator: RuntimeBinaryLocator
    private let diagnostics: DiagnosticsRecorder
    private let toolHandler: any ToolHandling
    private let approvalPolicy: any ToolApprovalPolicy
    private let timeoutPolicy: TimeoutPolicy
    private let eventSink: @Sendable (RuntimeEventEnvelope) -> Void

    private var processManager: CodexProcessManager?
    private var pendingApprovals: [String: RoutedToolCall] = [:]
    private var status: RuntimeStatusState = .starting
    private var restartPolicy: RestartPolicy
    private var createPayload = SessionCreatePayload()
    private var startupTimeoutTask: Task<Void, Never>?
    private var promptTimeoutTask: Task<Void, Never>?
    private var childSilenceTimeoutTask: Task<Void, Never>?
    private var idleTeardownTask: Task<Void, Never>?
    private var approvalTimeoutTasks: [String: Task<Void, Never>] = [:]

    init(
        sessionId: String,
        pathResolver: RuntimePathResolver,
        paths: RuntimePaths,
        binaryLocator: RuntimeBinaryLocator,
        diagnostics: DiagnosticsRecorder,
        toolHandler: any ToolHandling,
        approvalPolicy: any ToolApprovalPolicy,
        restartPolicy: RestartPolicy,
        timeoutPolicy: TimeoutPolicy,
        eventSink: @escaping @Sendable (RuntimeEventEnvelope) -> Void
    ) {
        self.sessionId = sessionId
        self.pathResolver = pathResolver
        self.paths = paths
        self.binaryLocator = binaryLocator
        self.diagnostics = diagnostics
        self.toolHandler = toolHandler
        self.approvalPolicy = approvalPolicy
        self.restartPolicy = restartPolicy
        self.timeoutPolicy = timeoutPolicy
        self.eventSink = eventSink
    }

    func startIfNeeded(createPayload: SessionCreatePayload) async throws {
        self.createPayload = createPayload
        guard processManager == nil else { return }

        cancelIdleTeardown()

        let binaryURL = try binaryLocator.locate()
        let environment = try pathResolver.genericEnvironment().merging([
            "CODEX_BRIDGE_SESSION_ID": sessionId,
            "CODEX_BRIDGE_WORKSPACE": try pathResolver.workspaceURL(sessionID: sessionId).path,
        ]) { _, newValue in newValue }

        let manager = CodexProcessManager(
            binaryURL: binaryURL,
            environment: environment,
            diagnostics: diagnostics,
            eventHandler: { [session = self] event in
                await session.handleRuntimeEvent(event)
            },
            terminationHandler: { [session = self] reason in
                await session.handleRuntimeTermination(reason: reason)
            }
        )
        try await manager.start()
        processManager = manager
        status = .starting
        armStartupTimeout()

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
        cancelIdleTeardown()

        if let processManager {
            try await processManager.send(request)
            armPromptTimeout()
            armChildSilenceTimeout()
        }
    }

    func resolveApproval(_ request: RuntimeRequestEnvelope) async throws {
        let resolution = try request.decodePayload(ApprovalResolutionPayload.self)
        guard let routedToolCall = pendingApprovals.removeValue(forKey: resolution.toolInvocationId) else {
            cancelApprovalTimeout(for: resolution.toolInvocationId)
            return
        }

        cancelApprovalTimeout(for: resolution.toolInvocationId)
        eventSink(
            RuntimeEventEnvelope(
                sessionId: sessionId,
                kind: .approvalResolved,
                payload: try? PayloadCoder.encode(routedToolCall.approvalResolvedPayload(decision: resolution.decision))
            )
        )

        if resolution.decision == .reject {
            try await forwardToolFailure(
                routedToolCall,
                summary: "User rejected \(routedToolCall.toolName.rawValue).",
                runtimeWarning: nil
            )
            return
        }

        do {
            try await executeTool(routedToolCall)
        } catch {
            try await forwardToolFailure(
                routedToolCall,
                summary: error.localizedDescription,
                runtimeWarning: runtimeWarningPayload(for: error, toolName: routedToolCall.toolName)
            )
        }
    }

    func cancel(_ request: RuntimeRequestEnvelope) async throws {
        pendingApprovals.removeAll()
        cancelApprovalTimeouts()
        cancelPromptTimeout()
        cancelChildSilenceTimeout()
        cancelIdleTeardown()
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
        cancelAllTimeouts()
        status = .stopped
        await processManager?.stop(reason: reason)
        processManager = nil
        let ended = RuntimeEventEnvelope(
            sessionId: sessionId,
            kind: .sessionEnded,
            payload: try? PayloadCoder.encode(SessionEndedPayload(reason: reason))
        )
        eventSink(ended)
    }

    private func handleRuntimeEvent(_ event: RuntimeEventEnvelope) async {
        switch event.kind {
        case .toolCallRequested:
            guard let toolCall = try? event.decodePayload(ToolCallPayload.self) else {
                await handleProtocolViolation("Invalid tool call payload.")
                return
            }
            cancelStartupTimeout()
            cancelPromptTimeout()
            cancelChildSilenceTimeout()
            await handleToolRequest(toolCall)
        case .assistantDelta:
            cancelStartupTimeout()
            cancelPromptTimeout()
            cancelIdleTeardown()
            status = .busy
            armChildSilenceTimeout()
            eventSink(event)
        case .assistantMessageCompleted:
            guard (try? event.decodePayload(CompletionPayload.self)) != nil else {
                await handleProtocolViolation("Invalid completion payload.")
                return
            }
            cancelStartupTimeout()
            cancelPromptTimeout()
            cancelChildSilenceTimeout()
            status = .ready
            scheduleIdleTeardown()
            eventSink(event)
        case .providerStatus, .runtimeStatus:
            guard let payload = try? event.decodePayload(RuntimeStatusPayload.self) else {
                await handleProtocolViolation("Invalid runtime status payload.")
                return
            }
            cancelStartupTimeout()
            status = payload.state
            switch payload.state {
            case .ready:
                cancelPromptTimeout()
                cancelChildSilenceTimeout()
                scheduleIdleTeardown()
            case .busy, .starting:
                cancelIdleTeardown()
                armChildSilenceTimeout()
            case .waitingForApproval:
                cancelPromptTimeout()
                cancelChildSilenceTimeout()
            case .failed:
                cancelChildSilenceTimeout()
                cancelIdleTeardown()
            case .interrupted, .stopped, .disconnected:
                cancelChildSilenceTimeout()
                cancelIdleTeardown()
            }
            eventSink(event)
        case .runtimeError:
            guard (try? event.decodePayload(RuntimeErrorPayload.self)) != nil else {
                await handleProtocolViolation("Invalid runtime error payload.")
                return
            }
            cancelStartupTimeout()
            cancelPromptTimeout()
            cancelChildSilenceTimeout()
            cancelIdleTeardown()
            status = .interrupted
            eventSink(event)
        case .sessionReady:
            guard (try? event.decodePayload(CompletionPayload.self)) != nil else {
                await handleProtocolViolation("Invalid session ready payload.")
                return
            }
            cancelStartupTimeout()
            eventSink(event)
        default:
            cancelStartupTimeout()
            eventSink(event)
        }
    }

    private func handleRuntimeTermination(reason: String) async {
        processManager = nil
        cancelAllTimeouts()

        guard !SessionTermination.ignoredReasons.contains(reason) else { return }

        if let payload = SessionTermination.payload(for: reason) {
            status = .interrupted
            eventSink(
                RuntimeEventEnvelope(
                    sessionId: sessionId,
                    kind: .serviceInterrupted,
                    payload: try? PayloadCoder.encode(payload)
                )
            )
            eventSink(
                RuntimeEventEnvelope(
                    sessionId: sessionId,
                    kind: .runtimeError,
                    payload: try? PayloadCoder.encode(payload)
                )
            )
            return
        }

        eventSink(
            RuntimeEventEnvelope(
                sessionId: sessionId,
                kind: .serviceInterrupted,
                payload: try? PayloadCoder.encode(
                    RuntimeErrorPayload(code: "runtime_interrupted", message: reason, retryable: true)
                )
            )
        )

        guard restartPolicy.registerCrash() else {
            status = .interrupted
            eventSink(
                RuntimeEventEnvelope(
                    sessionId: sessionId,
                    kind: .runtimeError,
                    payload: try? PayloadCoder.encode(
                        RuntimeErrorPayload(code: "runtime_crash", message: "Runtime exited unexpectedly.", retryable: true)
                    )
                )
            )
            return
        }

        do {
            try await startIfNeeded(createPayload: createPayload)
            status = .ready
            eventSink(
                RuntimeEventEnvelope(
                    sessionId: sessionId,
                    kind: .serviceRecovered,
                    payload: try? PayloadCoder.encode(RuntimeStatusPayload(state: .ready, detail: "Runtime restarted"))
                )
            )
        } catch {
            status = .interrupted
            eventSink(
                RuntimeEventEnvelope(
                    sessionId: sessionId,
                    kind: .runtimeError,
                    payload: try? PayloadCoder.encode(
                        RuntimeErrorPayload(code: "restart_failed", message: error.localizedDescription, retryable: false)
                    )
                )
            )
        }
    }

    private func handleToolRequest(_ toolCall: ToolCallPayload) async {
        let normalizedToolCall = ToolCallPayload(
            toolInvocationId: UUID().uuidString,
            toolName: toolCall.toolName,
            summary: toolCall.summary,
            requiresApproval: approvalPolicy.requiresExplicitApproval(for: toolCall.toolName),
            arguments: toolCall.arguments
        )
        let routedToolCall = RoutedToolCall(runtimeToolInvocationId: toolCall.toolInvocationId, hostToolCall: normalizedToolCall)

        eventSink(
            RuntimeEventEnvelope(
                sessionId: sessionId,
                kind: .toolCallRequested,
                payload: try? PayloadCoder.encode(normalizedToolCall)
            )
        )

        if normalizedToolCall.requiresApproval {
            pendingApprovals[normalizedToolCall.toolInvocationId] = routedToolCall
            armApprovalTimeout(for: routedToolCall)
            let approval = RuntimeEventEnvelope(
                sessionId: sessionId,
                kind: .approvalRequired,
                payload: try? PayloadCoder.encode(
                    routedToolCall.approvalRequiredPayload(reason: "This tool requires explicit host approval.")
                )
            )
            eventSink(approval)
            status = .waitingForApproval
            return
        }

        do {
            try await executeTool(routedToolCall)
        } catch {
            do {
                try await forwardToolFailure(
                    routedToolCall,
                    summary: error.localizedDescription,
                    runtimeWarning: runtimeWarningPayload(for: error, toolName: routedToolCall.toolName)
                )
            } catch {
                status = .interrupted
                eventSink(
                    RuntimeEventEnvelope(
                        sessionId: sessionId,
                        kind: .runtimeError,
                        payload: try? PayloadCoder.encode(
                            RuntimeErrorPayload(code: "tool_result_forward_failed", message: error.localizedDescription, retryable: false)
                        )
                    )
                )
            }
        }
    }

    private func executeTool(_ routedToolCall: RoutedToolCall) async throws {
        cancelPromptTimeout()
        cancelChildSilenceTimeout()
        cancelIdleTeardown()
        status = .busy

        eventSink(
            RuntimeEventEnvelope(
                sessionId: sessionId,
                kind: .toolCallStarted,
                payload: try? PayloadCoder.encode(routedToolCall.hostToolCall)
            )
        )

        let toolHandler = self.toolHandler
        let sessionID = self.sessionId
        let hostToolCall = routedToolCall.hostToolCall
        let toolTimeout = timeoutPolicy.toolExecution

        let hostResult = try await withThrowingTaskGroup(of: ToolResultPayload.self) { group in
            group.addTask {
                try await toolHandler.execute(toolCall: hostToolCall, sessionID: sessionID)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.timeoutNanoseconds(toolTimeout))
                throw SessionToolExecutionError.timedOut(routedToolCall.toolName)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        eventSink(
            RuntimeEventEnvelope(
                sessionId: sessionId,
                kind: hostResult.success ? .toolCallCompleted : .toolCallFailed,
                payload: try? PayloadCoder.encode(hostResult)
            )
        )

        if let processManager {
            try await processManager.send(
                RuntimeRequestEnvelope(
                    sessionId: sessionId,
                    kind: .toolResult,
                    payload: try PayloadCoder.encode(routedToolCall.runtimeResult(from: hostResult))
                )
            )
            armChildSilenceTimeout()
        } else {
            status = .ready
            scheduleIdleTeardown()
        }
    }

    private func runtimeWarningPayload(for error: Error, toolName: ToolID) -> RuntimeErrorPayload {
        if error is SessionToolExecutionError {
            return RuntimeErrorPayload(
                code: "tool_timeout",
                message: "Tool execution timed out for \(toolName.rawValue).",
                retryable: false
            )
        }

        return RuntimeErrorPayload(code: "tool_failed", message: error.localizedDescription, retryable: false)
    }

    private func forwardToolFailure(
        _ routedToolCall: RoutedToolCall,
        summary: String,
        runtimeWarning: RuntimeErrorPayload?
    ) async throws {
        let hostResult = routedToolCall.hostResult(success: false, summary: summary)

        eventSink(
            RuntimeEventEnvelope(
                sessionId: sessionId,
                kind: .toolCallFailed,
                payload: try? PayloadCoder.encode(hostResult)
            )
        )

        if let runtimeWarning {
            eventSink(
                RuntimeEventEnvelope(
                    sessionId: sessionId,
                    kind: .runtimeWarning,
                    payload: try? PayloadCoder.encode(runtimeWarning)
                )
            )
        }

        if let processManager {
            try await processManager.send(
                RuntimeRequestEnvelope(
                    sessionId: sessionId,
                    kind: .toolResult,
                    payload: try PayloadCoder.encode(routedToolCall.runtimeResult(from: hostResult))
                )
            )
            status = .busy
            armChildSilenceTimeout()
        } else {
            status = .ready
            scheduleIdleTeardown()
        }
    }

    private func handleProtocolViolation(_ message: String) async {
        await diagnostics.append(message, to: "runtime-service.log")
        if let processManager {
            await processManager.stop(reason: "protocol_violation")
        }
    }

    private func armStartupTimeout() {
        cancelStartupTimeout()
        startupTimeoutTask = makeTimeoutTask(after: timeoutPolicy.startup) {
            await self.processManager?.stop(reason: "startup_timeout")
        }
    }

    private func armPromptTimeout() {
        cancelPromptTimeout()
        promptTimeoutTask = makeTimeoutTask(after: timeoutPolicy.prompt) {
            await self.processManager?.stop(reason: "prompt_timeout")
        }
    }

    private func armChildSilenceTimeout() {
        cancelChildSilenceTimeout()
        childSilenceTimeoutTask = makeTimeoutTask(after: timeoutPolicy.childSilence) {
            await self.processManager?.stop(reason: "child_silence_timeout")
        }
    }

    private func armApprovalTimeout(for routedToolCall: RoutedToolCall) {
        cancelApprovalTimeout(for: routedToolCall.hostToolInvocationId)
        approvalTimeoutTasks[routedToolCall.hostToolInvocationId] = makeTimeoutTask(after: timeoutPolicy.approval) {
            await self.handleApprovalTimeout(for: routedToolCall.hostToolInvocationId)
        }
    }

    private func handleApprovalTimeout(for hostToolInvocationId: String) async {
        guard let routedToolCall = pendingApprovals.removeValue(forKey: hostToolInvocationId) else {
            cancelApprovalTimeout(for: hostToolInvocationId)
            return
        }

        cancelApprovalTimeout(for: hostToolInvocationId)
        eventSink(
            RuntimeEventEnvelope(
                sessionId: sessionId,
                kind: .approvalResolved,
                payload: try? PayloadCoder.encode(routedToolCall.approvalResolvedPayload(decision: ApprovalResolution.reject))
            )
        )

        try? await forwardToolFailure(
            routedToolCall,
            summary: "Approval timed out for \(routedToolCall.toolName.rawValue).",
            runtimeWarning: RuntimeErrorPayload(code: "approval_timeout", message: "Approval wait timed out.", retryable: false)
        )
    }

    private func scheduleIdleTeardown() {
        guard processManager != nil else { return }
        cancelIdleTeardown()
        idleTeardownTask = makeTimeoutTask(after: timeoutPolicy.idleTeardown) {
            await self.stop(reason: "idle_timeout")
        }
    }

    private func cancelStartupTimeout() {
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
    }

    private func cancelPromptTimeout() {
        promptTimeoutTask?.cancel()
        promptTimeoutTask = nil
    }

    private func cancelChildSilenceTimeout() {
        childSilenceTimeoutTask?.cancel()
        childSilenceTimeoutTask = nil
    }

    private func cancelIdleTeardown() {
        idleTeardownTask?.cancel()
        idleTeardownTask = nil
    }

    private func cancelApprovalTimeout(for hostToolInvocationId: String) {
        approvalTimeoutTasks.removeValue(forKey: hostToolInvocationId)?.cancel()
    }

    private func cancelApprovalTimeouts() {
        let tasks = approvalTimeoutTasks.values
        approvalTimeoutTasks.removeAll()
        for task in tasks {
            task.cancel()
        }
    }

    private func cancelAllTimeouts() {
        cancelStartupTimeout()
        cancelPromptTimeout()
        cancelChildSilenceTimeout()
        cancelIdleTeardown()
        cancelApprovalTimeouts()
    }

    private func makeTimeoutTask(after interval: TimeInterval, action: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(nanoseconds: Self.timeoutNanoseconds(interval))
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    private static func timeoutNanoseconds(_ interval: TimeInterval) -> UInt64 {
        UInt64(max(interval, 0) * 1_000_000_000)
    }
}
