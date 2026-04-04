import Foundation
import XCTest
@testable import CodexBridgeContract
@testable import CodexBridgeSupport
@testable import CodexBridgeServiceCore
@testable import CodexBridgeXPC

final class BrokerEdgeCaseCoverageTests: XCTestCase {
    func testBrokerOverridesRuntimeApprovalFlagForApprovalRequiredTool() async throws {
        let recorder = BrokerEventRecorder()
        let sessionID = "approval-override"
        let broker = try makeBroker(
            recorder: recorder,
            runtimeURL: try approvalOverrideRuntimeURL(sessionID: sessionID)
        )

        _ = try await broker.handle(.make(sessionId: sessionID, kind: .createSession, payload: SessionCreatePayload()))
        try await recorder.waitForKind(.providerStatus)

        _ = try await broker.handle(.make(sessionId: sessionID, kind: .sendPrompt, payload: PromptSubmission(prompt: "Run approval override flow")))

        let toolRequest = try await recorder.waitForToolRequest(toolName: DemoToolID.convertShader)
        XCTAssertTrue(toolRequest.requiresApproval, "The broker should override the runtime flag for approval-required tools.")

        let approval = try await recorder.waitForApproval(toolName: DemoToolID.convertShader)
        _ = try await broker.handle(
            .make(
                sessionId: sessionID,
                kind: .resolveApproval,
                payload: ApprovalResolutionPayload(toolInvocationId: approval.id, decision: .approve)
            )
        )

        let completion = try await recorder.waitForCompletion()
        XCTAssertEqual(completion.finalText, "fixture flow finished")
        XCTAssertEqual(recorder.count(of: .approvalRequired), 1)
        XCTAssertEqual(recorder.count(of: .approvalResolved), 1)
    }

    func testMalformedChildStdoutCausesProtocolViolationInterruption() async throws {
        let recorder = BrokerEventRecorder()
        let broker = try makeBroker(
            recorder: recorder,
            runtimeURL: try malformedRuntimeURL()
        )

        do {
            _ = try await broker.handle(.make(sessionId: "protocol-violation", kind: .createSession, payload: SessionCreatePayload()))
            XCTFail("Expected create_session to fail after malformed runtime stdout.")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains("malformed")
                  || error.localizedDescription.contains("invalid stdout")
                  || error.localizedDescription.contains("protocol")
                  || error.localizedDescription.contains("ready"),
                "Unexpected error: \(error.localizedDescription)",
            )
        }

        let error = try await recorder.waitForRuntimeError(code: "protocol_violation")
        XCTAssertEqual(error.code, "protocol_violation")
        XCTAssertFalse(error.retryable)
        try await recorder.waitForKind(.serviceInterrupted)
        XCTAssertFalse(recorder.kinds().contains(.serviceRecovered))
    }

    func testStartupTimeoutEmitsRuntimeErrorAndInterruption() async throws {
        let recorder = BrokerEventRecorder()
        let broker = try makeBroker(
            recorder: recorder,
            runtimeURL: try silentRuntimeURL(),
            timeoutPolicy: TimeoutPolicy(startup: 0.1, idleTeardown: 5)
        )

        do {
            _ = try await broker.handle(.make(sessionId: "startup-timeout", kind: .createSession, payload: SessionCreatePayload()))
            XCTFail("Expected create_session to fail when startup times out.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("timed out"), "Unexpected error: \(error.localizedDescription)")
        }

        let error = try await recorder.waitForRuntimeError(code: "startup_timeout")
        XCTAssertEqual(error.code, "startup_timeout")
        XCTAssertFalse(error.retryable)
        XCTAssertEqual(error.phase, "startup")
        XCTAssertEqual(error.details, "The bundled Codex runtime did not emit session_ready before the startup deadline.")
        XCTAssertEqual(error.terminationReason, "startup_timeout")
        XCTAssertTrue(error.logPath?.hasSuffix("/logs/runtime-service.log") == true)
        try await recorder.waitForKind(.serviceInterrupted)
        XCTAssertFalse(recorder.kinds().contains(.serviceRecovered))
    }

    func testConnectionHandlerReturnsStructuredRejectedReplyForStartupTimeout() async throws {
        let recorder = BrokerEventRecorder()
        let sessionID = "handler-startup-timeout"
        let broker = try makeBroker(
            recorder: recorder,
            runtimeURL: try silentRuntimeURL(),
            timeoutPolicy: TimeoutPolicy(startup: 0.1, idleTeardown: 5)
        )
        let handler = CodexBridgeConnectionHandler(broker: broker, client: nil)
        let request = try RuntimeRequestEnvelope.make(
            sessionId: sessionID,
            kind: .createSession,
            payload: SessionCreatePayload()
        )
        let requestData = try XPCEnvelopeCodec.encodeRequest(request)

        let responseData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            handler.send(requestData) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: XPCErrorFactory.message("Expected rejected reply payload."))
                    return
                }
                continuation.resume(returning: data)
            }
        }

        let reply = try XPCEnvelopeCodec.decodeResponse(responseData)
        XCTAssertFalse(reply.accepted)
        XCTAssertEqual(reply.requestId, request.requestId)
        XCTAssertEqual(reply.message, "Runtime startup timed out.")

        let payload = try XCTUnwrap(reply.payload?.decode(RuntimeErrorPayload.self))
        XCTAssertEqual(payload.code, "startup_timeout")
        XCTAssertEqual(payload.phase, "startup")
        XCTAssertEqual(payload.details, "The bundled Codex runtime did not emit session_ready before the startup deadline.")
        XCTAssertEqual(payload.terminationReason, "startup_timeout")
        XCTAssertTrue(payload.logPath?.hasSuffix("/logs/runtime-service.log") == true)
    }

    func testApprovalWaitTimeoutFailsToolAndIgnoresLateResolution() async throws {
        let recorder = BrokerEventRecorder()
        let sessionID = "approval-timeout"
        let broker = try makeBroker(
            recorder: recorder,
            runtimeURL: try approvalOverrideRuntimeURL(sessionID: sessionID),
            timeoutPolicy: TimeoutPolicy(approval: 0.1, idleTeardown: 5)
        )

        _ = try await broker.handle(.make(sessionId: sessionID, kind: .createSession, payload: SessionCreatePayload()))
        try await recorder.waitForKind(.providerStatus)

        _ = try await broker.handle(.make(sessionId: sessionID, kind: .sendPrompt, payload: PromptSubmission(prompt: "Run approval timeout flow")))

        let approval = try await recorder.waitForApproval(toolName: DemoToolID.convertShader)
        let warning = try await recorder.waitForWarning(code: "approval_timeout")
        XCTAssertEqual(warning.code, "approval_timeout")

        let failedResult = try await recorder.waitForFailedTool(toolName: DemoToolID.convertShader)
        XCTAssertTrue(failedResult.summary.contains("Approval timed out"))

        _ = try await broker.handle(
            .make(
                sessionId: sessionID,
                kind: .resolveApproval,
                payload: ApprovalResolutionPayload(toolInvocationId: approval.id, decision: .approve)
            )
        )

        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(recorder.count(of: .approvalResolved), 1, "Late approval should be ignored after timeout resolution.")

        let completion = try await recorder.waitForCompletion()
        XCTAssertEqual(completion.finalText, "fixture flow finished")
    }

    private func makeBroker(
        recorder: BrokerEventRecorder,
        runtimeURL: URL,
        approvalPolicy: any ToolApprovalPolicy = ApprovalPolicy(),
        timeoutPolicy: TimeoutPolicy = TimeoutPolicy()
    ) throws -> CodexSessionBroker {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-xpc-bridge-edge-cases-\(UUID().uuidString)", isDirectory: true)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }

        return try CodexSessionBroker(
            pathResolver: RuntimePathResolver(environment: ["CODEX_BRIDGE_ROOT": root.path]),
            binaryLocator: RuntimeBinaryLocator(environment: [:], bundledCandidates: [runtimeURL]),
            approvalPolicy: approvalPolicy,
            timeoutPolicy: timeoutPolicy
        ) { event in
            recorder.append(event)
        }
    }

    private func approvalOverrideRuntimeURL(sessionID: String) throws -> URL {
        let sessionReady = try encodedEventLine(
            sessionId: sessionID,
            kind: .sessionReady,
            payload: CompletionPayload(finalText: "Session ready")
        )
        let providerStatus = try encodedEventLine(
            sessionId: sessionID,
            kind: .providerStatus,
            payload: RuntimeStatusPayload(state: .ready, detail: "fixture-runtime")
        )
        let writeTool = try encodedEventLine(
            sessionId: sessionID,
            kind: .toolCallRequested,
            payload: ToolCallPayload(
                toolInvocationId: "runtime-write",
                toolName: DemoToolID.writeWorkspaceFile,
                summary: "Seed a workspace shader for conversion.",
                requiresApproval: false,
                arguments: [
                    "path": .string("drafts/input.glsl"),
                    "content": .string("void main() { gl_FragColor = vec4(1.0); }")
                ]
            )
        )
        let convertTool = try encodedEventLine(
            sessionId: sessionID,
            kind: .toolCallRequested,
            payload: ToolCallPayload(
                toolInvocationId: "runtime-convert",
                toolName: DemoToolID.convertShader,
                summary: "Convert the seeded shader.",
                requiresApproval: false,
                arguments: [
                    "sourcePath": .string("drafts/input.glsl"),
                    "targetPath": .string("drafts/output.wgsl")
                ]
            )
        )
        let completion = try encodedEventLine(
            sessionId: sessionID,
            kind: .assistantMessageCompleted,
            payload: CompletionPayload(finalText: "fixture flow finished")
        )

        let body = """
        #!/bin/sh
        read _ || exit 0
        cat <<'EOF_BOOT'
        \(sessionReady)
        \(providerStatus)
        EOF_BOOT
        read _ || exit 0
        cat <<'EOF_WRITE'
        \(writeTool)
        EOF_WRITE
        read _ || exit 0
        cat <<'EOF_CONVERT'
        \(convertTool)
        EOF_CONVERT
        read _ || exit 0
        cat <<'EOF_DONE'
        \(completion)
        EOF_DONE
        sleep 1
        """

        return try executableRuntime(named: "approval-override-runtime.sh", body: body)
    }

    private func malformedRuntimeURL() throws -> URL {
        try executableRuntime(
            named: "malformed-runtime.sh",
            body: "#!/bin/sh\nprintf 'not-json\\n'\nsleep 5\n"
        )
    }

    private func silentRuntimeURL() throws -> URL {
        try executableRuntime(
            named: "silent-runtime.sh",
            body: "#!/bin/sh\nsleep 5\n"
        )
    }

    private func encodedEventLine<P: Encodable>(sessionId: String, kind: RuntimeEventKind, payload: P) throws -> String {
        let event = try RuntimeEventEnvelope.make(sessionId: sessionId, kind: kind, payload: payload)
        guard let line = String(data: try JSONLineCodec.encodeLine(event), encoding: .utf8) else {
            throw EdgeCaseHarnessError.invalidFixture("Unable to encode fixture event line.")
        }
        return line.trimmingCharacters(in: .newlines)
    }

    private func executableRuntime(named: String, body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-xpc-bridge-edge-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let runtimeURL = directory.appendingPathComponent(named)
        try body.write(to: runtimeURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeURL.path)
        return runtimeURL
    }
}

private final class BrokerEventRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.codex.bridge.edge-cases.recorder")
    private var events: [RuntimeEventEnvelope] = []

    func append(_ event: RuntimeEventEnvelope) {
        queue.sync {
            events.append(event)
        }
    }

    func kinds() -> [RuntimeEventKind] {
        queue.sync { events.map(\.kind) }
    }

    func count(of kind: RuntimeEventKind) -> Int {
        queue.sync { events.filter { $0.kind == kind }.count }
    }

    func waitForKind(_ kind: RuntimeEventKind, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let hasKind = queue.sync { events.contains(where: { $0.kind == kind }) }
            if hasKind { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw EdgeCaseHarnessError.timeout("event \(kind.rawValue)")
    }

    func waitForToolRequest(toolName: ToolID, timeout: TimeInterval = 5) async throws -> ToolCallPayload {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let payload = queue.sync {
                events
                    .filter { $0.kind == .toolCallRequested }
                    .compactMap { try? $0.decodePayload(ToolCallPayload.self) }
                    .last(where: { $0.toolName == toolName })
            }
            if let payload { return payload }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw EdgeCaseHarnessError.timeout("tool request \(toolName.rawValue)")
    }

    func waitForApproval(toolName: ToolID, timeout: TimeInterval = 5) async throws -> PendingApprovalRecord {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let approval = queue.sync {
                events
                    .filter { $0.kind == .approvalRequired }
                    .compactMap { try? $0.decodePayload(ApprovalRequiredPayload.self) }
                    .last(where: { $0.toolName == toolName })
            }
            if let approval {
                return PendingApprovalRecord(id: approval.toolInvocationId, toolName: approval.toolName)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw EdgeCaseHarnessError.timeout("approval \(toolName.rawValue)")
    }

    func waitForWarning(code: String, timeout: TimeInterval = 5) async throws -> RuntimeErrorPayload {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let warning = queue.sync {
                events
                    .filter { $0.kind == .runtimeWarning }
                    .compactMap { try? $0.decodePayload(RuntimeErrorPayload.self) }
                    .last(where: { $0.code == code })
            }
            if let warning { return warning }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw EdgeCaseHarnessError.timeout("warning \(code)")
    }

    func waitForRuntimeError(code: String, timeout: TimeInterval = 5) async throws -> RuntimeErrorPayload {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let error = queue.sync {
                events
                    .filter { $0.kind == .runtimeError }
                    .compactMap { try? $0.decodePayload(RuntimeErrorPayload.self) }
                    .last(where: { $0.code == code })
            }
            if let error { return error }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw EdgeCaseHarnessError.timeout("runtime error \(code)")
    }

    func waitForFailedTool(toolName: ToolID, timeout: TimeInterval = 5) async throws -> ToolResultPayload {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let payload = queue.sync {
                events
                    .filter { $0.kind == .toolCallFailed }
                    .compactMap { try? $0.decodePayload(ToolResultPayload.self) }
                    .last(where: { $0.toolName == toolName })
            }
            if let payload { return payload }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw EdgeCaseHarnessError.timeout("failed tool \(toolName.rawValue)")
    }

    func waitForCompletion(timeout: TimeInterval = 5) async throws -> CompletionPayload {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let completion = queue.sync {
                events
                    .filter { $0.kind == .assistantMessageCompleted }
                    .compactMap { try? $0.decodePayload(CompletionPayload.self) }
                    .last
            }
            if let completion { return completion }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw EdgeCaseHarnessError.timeout("completion")
    }
}

private struct PendingApprovalRecord {
    let id: String
    let toolName: ToolID
}

private enum EdgeCaseHarnessError: LocalizedError {
    case timeout(String)
    case invalidFixture(String)

    var errorDescription: String? {
        switch self {
        case .timeout(let value):
            return "Timed out waiting for \(value)."
        case .invalidFixture(let value):
            return value
        }
    }
}
