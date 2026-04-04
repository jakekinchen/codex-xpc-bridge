import Foundation

public struct ToolID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

public enum DemoToolID {
    public static let importShader: ToolID = "import_shader"
    public static let convertShader: ToolID = "convert_shader"
    public static let validateShader: ToolID = "validate_shader"
    public static let capturePreview: ToolID = "capture_preview"
    public static let saveStyleProfile: ToolID = "save_style_profile"
    public static let saveToLibrary: ToolID = "save_to_library"
    public static let readWorkspaceFile: ToolID = "read_workspace_file"
    public static let writeWorkspaceFile: ToolID = "write_workspace_file"
}

public enum RuntimeRequestKind: String, Codable, Sendable {
    case createSession = "create_session"
    case sendPrompt = "send_prompt"
    case cancelOperation = "cancel_operation"
    case resolveApproval = "resolve_approval"
    case terminateSession = "terminate_session"
    case queryRuntimeStatus = "query_runtime_status"
    case toolResult = "tool_result"
    case ping = "ping"
}

public enum RuntimeEventKind: String, Codable, Sendable {
    case sessionReady = "session_ready"
    case assistantDelta = "assistant_delta"
    case assistantMessageCompleted = "assistant_message_completed"
    case toolCallRequested = "tool_call_requested"
    case approvalRequired = "approval_required"
    case approvalResolved = "approval_resolved"
    case toolCallStarted = "tool_call_started"
    case toolCallCompleted = "tool_call_completed"
    case toolCallFailed = "tool_call_failed"
    case runtimeWarning = "runtime_warning"
    case runtimeError = "runtime_error"
    case sessionEnded = "session_ended"
    case serviceInterrupted = "service_interrupted"
    case serviceRecovered = "service_recovered"
    case runtimeStatus = "runtime_status"
    case providerStatus = "provider_status"
}

public enum ApprovalResolution: String, Codable, Sendable {
    case approve
    case reject
}

public enum RuntimeStatusState: String, Codable, Sendable {
    case disconnected
    case starting
    case ready
    case busy
    case waitingForApproval
    case interrupted
    case failed
    case stopped
}

public struct RuntimeRequestEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let requestId: String
    public let sessionId: String
    public let conversationId: String?
    public let timestamp: Date
    public let kind: RuntimeRequestKind
    public let payload: JSONValue?

    public init(
        protocolVersion: Int = 1,
        requestId: String = UUID().uuidString,
        sessionId: String,
        conversationId: String? = nil,
        timestamp: Date = Date(),
        kind: RuntimeRequestKind,
        payload: JSONValue? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.requestId = requestId
        self.sessionId = sessionId
        self.conversationId = conversationId
        self.timestamp = timestamp
        self.kind = kind
        self.payload = payload
    }
}

public struct RuntimeReplyEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let requestId: String
    public let accepted: Bool
    public let message: String?
    public let payload: JSONValue?

    public init(
        protocolVersion: Int = 1,
        requestId: String,
        accepted: Bool,
        message: String? = nil,
        payload: JSONValue? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.requestId = requestId
        self.accepted = accepted
        self.message = message
        self.payload = payload
    }
}

public struct RuntimeEventEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let eventId: String
    public let sessionId: String
    public let conversationId: String?
    public let timestamp: Date
    public let kind: RuntimeEventKind
    public let payload: JSONValue?

    public init(
        protocolVersion: Int = 1,
        eventId: String = UUID().uuidString,
        sessionId: String,
        conversationId: String? = nil,
        timestamp: Date = Date(),
        kind: RuntimeEventKind,
        payload: JSONValue? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.eventId = eventId
        self.sessionId = sessionId
        self.conversationId = conversationId
        self.timestamp = timestamp
        self.kind = kind
        self.payload = payload
    }
}

public struct SessionCreatePayload: Codable, Equatable, Sendable {
    public let conversationTitle: String?

    public init(conversationTitle: String? = nil) {
        self.conversationTitle = conversationTitle
    }
}

public typealias SessionConfiguration = SessionCreatePayload

public struct PromptSubmission: Codable, Equatable, Sendable {
    public let prompt: String

    public init(prompt: String) {
        self.prompt = prompt
    }
}

public struct AckPayload: Codable, Equatable, Sendable {
    public let acceptedKind: String
    public let detail: String

    public init(acceptedKind: String, detail: String) {
        self.acceptedKind = acceptedKind
        self.detail = detail
    }
}

public struct RuntimeStatusPayload: Codable, Equatable, Sendable {
    public let state: RuntimeStatusState
    public let detail: String?

    public init(state: RuntimeStatusState, detail: String? = nil) {
        self.state = state
        self.detail = detail
    }

    public init(status: RuntimeStatusState, detail: String? = nil) {
        self.state = status
        self.detail = detail
    }

    public var status: RuntimeStatusState { state }
}

public struct AssistantDeltaPayload: Codable, Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct CompletionPayload: Codable, Equatable, Sendable {
    public let finalText: String

    public init(finalText: String) {
        self.finalText = finalText
    }
}

public struct RuntimeErrorPayload: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let retryable: Bool
    public let details: String?
    public let phase: String?
    public let logPath: String?
    public let terminationReason: String?

    public init(
        code: String,
        message: String,
        retryable: Bool,
        details: String? = nil,
        phase: String? = nil,
        logPath: String? = nil,
        terminationReason: String? = nil
    ) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.details = details
        self.phase = phase
        self.logPath = logPath
        self.terminationReason = terminationReason
    }

    public init(
        code: String,
        message: String,
        isRecoverable: Bool,
        details: String? = nil,
        phase: String? = nil,
        logPath: String? = nil,
        terminationReason: String? = nil
    ) {
        self.code = code
        self.message = message
        self.retryable = isRecoverable
        self.details = details
        self.phase = phase
        self.logPath = logPath
        self.terminationReason = terminationReason
    }

    public var isRecoverable: Bool { retryable }
}

public struct ErrorPayload: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let recoverable: Bool

    public init(code: String, message: String, recoverable: Bool) {
        self.code = code
        self.message = message
        self.recoverable = recoverable
    }
}

public struct SessionEndedPayload: Codable, Equatable, Sendable {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

public struct ApprovalResolutionPayload: Codable, Equatable, Sendable {
    public let toolInvocationId: String
    public let decision: ApprovalResolution

    public init(toolInvocationId: String, decision: ApprovalResolution) {
        self.toolInvocationId = toolInvocationId
        self.decision = decision
    }
}

public struct ApprovalRequiredPayload: Codable, Equatable, Sendable {
    public let toolInvocationId: String
    public let toolName: ToolID
    public let reason: String
    public let inputSummary: String

    public var toolID: ToolID { toolName }

    public init(toolInvocationId: String, toolName: ToolID, reason: String, inputSummary: String) {
        self.toolInvocationId = toolInvocationId
        self.toolName = toolName
        self.reason = reason
        self.inputSummary = inputSummary
    }
}

public struct ApprovalResolvedPayload: Codable, Equatable, Sendable {
    public let toolInvocationId: String
    public let toolName: ToolID
    public let decision: ApprovalResolution

    public var toolID: ToolID { toolName }

    public init(toolInvocationId: String, toolName: ToolID, decision: ApprovalResolution) {
        self.toolInvocationId = toolInvocationId
        self.toolName = toolName
        self.decision = decision
    }
}

public struct ToolCallPayload: Codable, Equatable, Sendable, Identifiable {
    public let toolInvocationId: String
    public let toolName: ToolID
    public let summary: String
    public let requiresApproval: Bool
    public let arguments: [String: JSONValue]

    public var id: String { toolInvocationId }
    public var invocationId: String { toolInvocationId }
    public var toolID: ToolID { toolName }

    public init(
        toolInvocationId: String = UUID().uuidString,
        toolName: ToolID,
        summary: String,
        requiresApproval: Bool,
        arguments: [String: JSONValue]
    ) {
        self.toolInvocationId = toolInvocationId
        self.toolName = toolName
        self.summary = summary
        self.requiresApproval = requiresApproval
        self.arguments = arguments
    }

    public init(
        invocationId: String = UUID().uuidString,
        toolName: ToolID,
        summary: String,
        requiresApproval: Bool,
        arguments: [String: JSONValue]
    ) {
        self.init(toolInvocationId: invocationId, toolName: toolName, summary: summary, requiresApproval: requiresApproval, arguments: arguments)
    }
}

public typealias ToolInvocationPayload = ToolCallPayload

public struct ToolResultPayload: Codable, Equatable, Sendable {
    public let toolInvocationId: String
    public let toolName: ToolID
    public let success: Bool
    public let summary: String
    public let outputs: [String: JSONValue]
    public let artifactPaths: [String]

    public var invocationId: String { toolInvocationId }
    public var message: String { summary }
    public var output: JSONValue? { outputs.isEmpty ? nil : .object(outputs) }
    public var toolID: ToolID { toolName }

    public init(
        toolInvocationId: String,
        toolName: ToolID,
        success: Bool,
        summary: String,
        outputs: [String: JSONValue] = [:],
        artifactPaths: [String] = []
    ) {
        self.toolInvocationId = toolInvocationId
        self.toolName = toolName
        self.success = success
        self.summary = summary
        self.outputs = outputs
        self.artifactPaths = artifactPaths
    }

    public init(
        invocationId: String,
        toolName: ToolID,
        success: Bool,
        message: String,
        output: JSONValue? = nil,
        artifactPaths: [String] = []
    ) {
        self.init(
            toolInvocationId: invocationId,
            toolName: toolName,
            success: success,
            summary: message,
            outputs: output?.objectValue ?? [:],
            artifactPaths: artifactPaths
        )
    }
}

public enum PayloadCoder {
    public static func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder.codexBridge.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONValue(any: object)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue?) throws -> T {
        let data = try JSONEncoder.codexBridge.encode(value ?? .null)
        return try JSONDecoder.codexBridge.decode(T.self, from: data)
    }
}

public extension RuntimeRequestEnvelope {
    static func make<T: Encodable>(sessionId: String, conversationId: String? = nil, kind: RuntimeRequestKind, payload: T) throws -> RuntimeRequestEnvelope {
        try RuntimeRequestEnvelope(sessionId: sessionId, conversationId: conversationId, kind: kind, payload: PayloadCoder.encode(payload))
    }

    func decodePayload<T: Decodable>(_ type: T.Type) throws -> T {
        try PayloadCoder.decode(type, from: payload)
    }
}

public extension RuntimeEventEnvelope {
    static func make<T: Encodable>(sessionId: String, conversationId: String? = nil, kind: RuntimeEventKind, payload: T) throws -> RuntimeEventEnvelope {
        try RuntimeEventEnvelope(sessionId: sessionId, conversationId: conversationId, kind: kind, payload: PayloadCoder.encode(payload))
    }

    func decodePayload<T: Decodable>(_ type: T.Type) throws -> T {
        try PayloadCoder.decode(type, from: payload)
    }
}
