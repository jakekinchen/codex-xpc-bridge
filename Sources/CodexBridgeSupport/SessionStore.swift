import Foundation
import CodexBridgeContract

public enum TranscriptRole: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
    case tool
    case warning
    case error
}

public struct TranscriptEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let role: TranscriptRole
    public var text: String
    public var isStreaming: Bool
    public let createdAt: Date

    public init(id: String = UUID().uuidString, role: TranscriptRole, text: String, isStreaming: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
        self.createdAt = createdAt
    }
}

public struct PendingApproval: Identifiable, Equatable, Sendable {
    public let id: String
    public let toolName: ToolName
    public let reason: String
    public let summary: String
}

public struct BridgeSessionState: Equatable, Sendable {
    public var status: RuntimeStatusState
    public var statusDetail: String
    public var transcript: [TranscriptEntry]
    public var pendingApproval: PendingApproval?
    public var artifactPaths: [String]

    public init(
        status: RuntimeStatusState = .disconnected,
        statusDetail: String = "Not connected",
        transcript: [TranscriptEntry] = [],
        pendingApproval: PendingApproval? = nil,
        artifactPaths: [String] = []
    ) {
        self.status = status
        self.statusDetail = statusDetail
        self.transcript = transcript
        self.pendingApproval = pendingApproval
        self.artifactPaths = artifactPaths
    }
}

public enum SessionStore {
    public static func makeUserEntry(prompt: String) -> TranscriptEntry {
        TranscriptEntry(role: .user, text: prompt)
    }

    public static func reduce(_ state: inout BridgeSessionState, event: RuntimeEventEnvelope) {
        switch event.kind {
        case .sessionReady:
            state.status = .ready
            state.statusDetail = "Session ready"
        case .runtimeStatus, .providerStatus:
            if let payload = try? event.decodePayload(RuntimeStatusPayload.self) {
                state.status = payload.state
                state.statusDetail = payload.detail ?? payload.state.rawValue
            }
        case .assistantDelta:
            guard let payload = try? event.decodePayload(AssistantDeltaPayload.self) else { return }
            if let lastIndex = state.transcript.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                state.transcript[lastIndex].text += payload.text
            } else {
                state.transcript.append(TranscriptEntry(role: .assistant, text: payload.text, isStreaming: true))
            }
        case .assistantMessageCompleted:
            let finalText = (try? event.decodePayload(CompletionPayload.self).finalText) ?? state.transcript.last(where: { $0.role == .assistant })?.text ?? "Completed."
            if let lastIndex = state.transcript.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                state.transcript[lastIndex].text = finalText
                state.transcript[lastIndex].isStreaming = false
            } else {
                state.transcript.append(TranscriptEntry(role: .assistant, text: finalText))
            }
            state.status = .ready
            state.statusDetail = "Turn completed"
        case .toolCallRequested:
            guard let payload = try? event.decodePayload(ToolCallPayload.self) else { return }
            state.transcript.append(TranscriptEntry(role: .tool, text: "Requested \(payload.toolName.rawValue): \(payload.summary)"))
            state.status = payload.requiresApproval ? .waitingForApproval : .busy
            state.statusDetail = payload.requiresApproval ? "Awaiting approval" : "Running tool"
        case .approvalRequired:
            guard let payload = try? event.decodePayload(ApprovalRequiredPayload.self) else { return }
            state.pendingApproval = PendingApproval(id: payload.toolInvocationId, toolName: payload.toolName, reason: payload.reason, summary: payload.inputSummary)
            state.status = .waitingForApproval
            state.statusDetail = payload.reason
        case .approvalResolved:
            state.pendingApproval = nil
            state.status = .busy
            state.statusDetail = "Approval resolved"
        case .toolCallStarted:
            if let payload = try? event.decodePayload(ToolCallPayload.self) {
                state.transcript.append(TranscriptEntry(role: .tool, text: "Running \(payload.toolName.rawValue)"))
            }
        case .toolCallCompleted:
            guard let payload = try? event.decodePayload(ToolResultPayload.self) else { return }
            state.transcript.append(TranscriptEntry(role: .tool, text: payload.summary))
            for path in payload.artifactPaths where !state.artifactPaths.contains(path) {
                state.artifactPaths.append(path)
            }
        case .toolCallFailed:
            if let payload = try? event.decodePayload(ToolResultPayload.self) {
                state.transcript.append(TranscriptEntry(role: .error, text: payload.summary))
            } else if let payload = try? event.decodePayload(RuntimeErrorPayload.self) {
                state.transcript.append(TranscriptEntry(role: .error, text: payload.message))
                state.statusDetail = payload.message
            }
            state.status = .failed
        case .runtimeWarning:
            if let payload = try? event.decodePayload(RuntimeErrorPayload.self) {
                state.transcript.append(TranscriptEntry(role: .warning, text: payload.message))
                state.statusDetail = payload.message
            } else if let payload = try? event.decodePayload(ErrorPayload.self) {
                state.transcript.append(TranscriptEntry(role: .warning, text: payload.message))
                state.statusDetail = payload.message
            }
        case .runtimeError, .serviceInterrupted:
            if let payload = try? event.decodePayload(RuntimeErrorPayload.self) {
                state.transcript.append(TranscriptEntry(role: .error, text: payload.message))
                state.statusDetail = payload.message
            }
            state.pendingApproval = nil
            state.status = .interrupted
        case .serviceRecovered:
            state.status = .ready
            state.statusDetail = "Service recovered"
        case .sessionEnded:
            state.pendingApproval = nil
            state.status = .disconnected
            state.statusDetail = "Session ended"
        }
    }
}
