import Foundation
import XCTest
@testable import CodexBridgeContract
@testable import CodexBridgeSupport
@testable import CodexBridgeServiceCore

final class CodexSessionBrokerIntegrationTests: XCTestCase {
    func testBrokerRunsFullBoundedPipelineThroughBundledCodexRuntime() async throws {
        let recorder = EventRecorder()
        let broker = try makeBroker(recorder: recorder)

        let sessionId = "integration-full"
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .createSession, payload: SessionCreatePayload(conversationTitle: "Fixture")))
        try await recorder.waitForKind(.providerStatus)
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .sendPrompt, payload: PromptSubmission(prompt: "Run the full bounded pipeline and save it to the library")))

        let firstApproval = try await recorder.waitForApproval(toolName: DemoToolID.convertShader)
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .resolveApproval, payload: ApprovalResolutionPayload(toolInvocationId: firstApproval.id, decision: .approve)))

        let secondApproval = try await recorder.waitForApproval(toolName: DemoToolID.saveToLibrary)
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .resolveApproval, payload: ApprovalResolutionPayload(toolInvocationId: secondApproval.id, decision: .approve)))

        let completion = try await recorder.waitForCompletion()
        XCTAssertEqual(completion.finalText, "Completed bounded pipeline.")

        let completedResults = try recorder.completedToolResults()
        XCTAssertEqual(completedResults.map(\.toolName), [DemoToolID.writeWorkspaceFile, DemoToolID.convertShader, DemoToolID.validateShader, DemoToolID.capturePreview, DemoToolID.saveToLibrary])
        XCTAssertEqual(completedResults.count, 5)
        XCTAssertTrue(completedResults.allSatisfy(\.success))
        XCTAssertTrue(completedResults.flatMap(\.artifactPaths).allSatisfy { FileManager.default.fileExists(atPath: $0) })

        let kinds = recorder.kinds()
        XCTAssertTrue(kinds.contains(.sessionReady))
        XCTAssertTrue(kinds.contains(.toolCallRequested))
        XCTAssertTrue(kinds.contains(.approvalRequired))
        XCTAssertTrue(kinds.contains(.approvalResolved))
        XCTAssertTrue(kinds.contains(.toolCallStarted))
        XCTAssertTrue(kinds.contains(.toolCallCompleted))
        XCTAssertTrue(kinds.contains(.assistantMessageCompleted))
    }

    func testBrokerPropagatesRejectedApprovalAsTerminalFailure() async throws {
        let recorder = EventRecorder()
        let broker = try makeBroker(recorder: recorder)

        let sessionId = "integration-reject"
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .createSession, payload: SessionCreatePayload()))
        try await recorder.waitForKind(.providerStatus)
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .sendPrompt, payload: PromptSubmission(prompt: "Run the full bounded pipeline and save it to the library")))

        let firstApproval = try await recorder.waitForApproval(toolName: DemoToolID.convertShader)
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .resolveApproval, payload: ApprovalResolutionPayload(toolInvocationId: firstApproval.id, decision: .reject)))

        let completion = try await recorder.waitForCompletion()
        XCTAssertEqual(completion.finalText, "Flow stopped after rejected or failed tool.")

        let completedResults = try recorder.completedToolResults()
        XCTAssertEqual(completedResults.map(\.toolName), [DemoToolID.writeWorkspaceFile])

        let kinds = recorder.kinds()
        XCTAssertEqual(kinds.filter { $0 == .approvalRequired }.count, 1)
    }

    func testBrokerReportsRuntimeStatusAndCancellationFromBundledCodexRuntime() async throws {
        let recorder = EventRecorder()
        let broker = try makeBroker(recorder: recorder)

        let sessionId = "integration-status"
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .createSession, payload: SessionCreatePayload()))
        try await recorder.waitForKind(.providerStatus)

        let statusReply = try await broker.handle(RuntimeRequestEnvelope(sessionId: sessionId, kind: .queryRuntimeStatus))
        let status = try PayloadCoder.decode(RuntimeStatusPayload.self, from: statusReply.payload)
        XCTAssertEqual(status.state, .ready)

        _ = try await broker.handle(.make(sessionId: sessionId, kind: .sendPrompt, payload: PromptSubmission(prompt: "Run the bounded pipeline")))
        _ = try await broker.handle(RuntimeRequestEnvelope(sessionId: sessionId, kind: .cancelOperation))

        let completion = try await recorder.waitForCompletion()
        XCTAssertEqual(completion.finalText, "Cancelled.")

        let warning = try await recorder.waitForWarning()
        XCTAssertEqual(warning.code, "cancelled")
    }

    func testBrokerOverridesRuntimeApprovalHintForApprovalRequiredTool() async throws {
        let recorder = EventRecorder()
        let sessionId = "integration-approval-override"
        let broker = try makeBroker(
            recorder: recorder,
            binaryLocator: RuntimeBinaryLocator(
                environment: [:],
                bundledCandidates: [try approvalOverrideRuntimeURL(sessionId: sessionId)]
            )
        )

        _ = try await broker.handle(.make(sessionId: sessionId, kind: .createSession, payload: SessionCreatePayload()))
        try await recorder.waitForKind(.providerStatus)
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .sendPrompt, payload: PromptSubmission(prompt: "Trigger approval-required tool request")))

        let requestedTool = try await recorder.waitForToolRequest(toolName: DemoToolID.convertShader)
        XCTAssertTrue(requestedTool.requiresApproval)

        let approval = try await recorder.waitForApproval(toolName: DemoToolID.convertShader)
        XCTAssertEqual(approval.id, requestedTool.toolInvocationId)

        _ = try await broker.handle(.make(sessionId: sessionId, kind: .resolveApproval, payload: ApprovalResolutionPayload(toolInvocationId: approval.id, decision: .reject)))
    }

    func testBrokerTimesOutApprovalWaitAndIgnoresLateApprovalResolution() async throws {
        let recorder = EventRecorder()
        let broker = try makeBroker(
            recorder: recorder,
            timeoutPolicy: TimeoutPolicy(startup: 10, approval: 0.1)
        )

        let sessionId = "integration-approval-timeout"
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .createSession, payload: SessionCreatePayload()))
        try await recorder.waitForKind(.providerStatus)
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .sendPrompt, payload: PromptSubmission(prompt: "Run the full bounded pipeline and save it to the library")))

        let approval = try await recorder.waitForApproval(toolName: DemoToolID.convertShader)
        try await Task.sleep(for: .milliseconds(250))
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .resolveApproval, payload: ApprovalResolutionPayload(toolInvocationId: approval.id, decision: .approve)))

        let completion = try await recorder.waitForCompletion()
        XCTAssertEqual(completion.finalText, "Flow stopped after rejected or failed tool.")

        let warning = try await recorder.waitForWarning(code: "approval_timeout")
        XCTAssertEqual(warning.code, "approval_timeout")

        let failedResults = recorder.failedToolResults()
        XCTAssertTrue(failedResults.contains(where: { $0.toolName == DemoToolID.convertShader && $0.summary.contains("Approval timed out") }))
        XCTAssertFalse(try recorder.completedToolResults().contains(where: { $0.toolName == DemoToolID.convertShader }))
    }

    func testBrokerReportsStartupTimeoutForSilentRuntime() async throws {
        let recorder = EventRecorder()
        let broker = try makeBroker(
            recorder: recorder,
            binaryLocator: RuntimeBinaryLocator(
                environment: [:],
                bundledCandidates: [try executableRuntime(named: "silent-runtime.sh", body: "#!/bin/sh\nsleep 5\n")]
            ),
            timeoutPolicy: TimeoutPolicy(startup: 0.1, approval: 5)
        )

        let sessionId = "integration-startup-timeout"
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .createSession, payload: SessionCreatePayload()))

        let error = try await recorder.waitForRuntimeError(code: "startup_timeout")
        XCTAssertEqual(error.code, "startup_timeout")
        XCTAssertTrue(recorder.kinds().contains(.serviceInterrupted))
        XCTAssertFalse(recorder.kinds().contains(.serviceRecovered))
    }

    func testBrokerReportsProtocolViolationForMalformedRuntimeStdout() async throws {
        let recorder = EventRecorder()
        let broker = try makeBroker(
            recorder: recorder,
            binaryLocator: RuntimeBinaryLocator(
                environment: [:],
                bundledCandidates: [try executableRuntime(named: "malformed-runtime.sh", body: "#!/bin/sh\nprintf 'not-json\\n'\nsleep 5\n")]
            ),
            timeoutPolicy: TimeoutPolicy(startup: 1, approval: 5)
        )

        let sessionId = "integration-protocol-violation"
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .createSession, payload: SessionCreatePayload()))

        let error = try await recorder.waitForRuntimeError(code: "protocol_violation")
        XCTAssertEqual(error.code, "protocol_violation")
        XCTAssertTrue(recorder.kinds().contains(.serviceInterrupted))
        XCTAssertFalse(recorder.kinds().contains(.serviceRecovered))
    }

    private func makeBroker(
        recorder: EventRecorder,
        binaryLocator: RuntimeBinaryLocator? = nil,
        timeoutPolicy: TimeoutPolicy = TimeoutPolicy(),
        toolHandlerFactory: @escaping ToolHandlingFactory = { paths, resolver in
            DemoToolExecutor(paths: paths, resolver: resolver)
        }
    ) throws -> CodexSessionBroker {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-xpc-bridge-integration-\(UUID().uuidString)", isDirectory: true)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        let resolver = RuntimePathResolver(environment: ["CODEX_BRIDGE_ROOT": root.path])
        let resolvedBinaryLocator = try binaryLocator ?? RuntimeBinaryLocator(environment: [:], bundledCandidates: [bundledRuntimeURL()])
        return try CodexSessionBroker(
            pathResolver: resolver,
            binaryLocator: resolvedBinaryLocator,
            timeoutPolicy: timeoutPolicy,
            toolHandlerFactory: toolHandlerFactory
        ) { event in
            recorder.append(event)
        }
    }

    private func approvalOverrideRuntimeURL(sessionId: String) throws -> URL {
        let sessionReady = try encodedEventLine(
            sessionId: sessionId,
            kind: .sessionReady,
            payload: CompletionPayload(finalText: "Session ready")
        )
        let providerStatus = try encodedEventLine(
            sessionId: sessionId,
            kind: .providerStatus,
            payload: RuntimeStatusPayload(state: .ready, detail: "fixture-runtime")
        )
        let assistantDelta = try encodedEventLine(
            sessionId: sessionId,
            kind: .assistantDelta,
            payload: AssistantDeltaPayload(text: "Working ")
        )
        let toolRequest = try encodedEventLine(
            sessionId: sessionId,
            kind: .toolCallRequested,
            payload: ToolCallPayload(
                toolInvocationId: "fixture-convert",
                toolName: DemoToolID.convertShader,
                summary: "Convert fixture shader",
                requiresApproval: false,
                arguments: [:]
            )
        )

        let body = """
        #!/bin/sh
        read _ || exit 0
        cat <<'EOF_SESSION'
        \(sessionReady)
        \(providerStatus)
        EOF_SESSION
        read _ || exit 0
        cat <<'EOF_TOOL'
        \(assistantDelta)
        \(toolRequest)
        EOF_TOOL
        read _ || exit 0
        """

        return try executableRuntime(named: "approval-override-runtime.sh", body: body)
    }

    private func encodedEventLine<P: Encodable>(sessionId: String, kind: RuntimeEventKind, payload: P) throws -> String {
        let event = try RuntimeEventEnvelope.make(sessionId: sessionId, kind: kind, payload: payload)
        guard let line = String(data: try JSONLineCodec.encodeLine(event), encoding: .utf8) else {
            throw IntegrationHarnessError.invalidFixture("Unable to encode fixture event line.")
        }
        return line.trimmingCharacters(in: .newlines)
    }

    private func executableRuntime(named: String, body: String) throws -> URL {
        let runtimeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-xpc-bridge-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        let runtimeURL = runtimeDirectory.appendingPathComponent(named)
        try body.write(to: runtimeURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtimeURL.path)
        return runtimeURL
    }

    private func bundledRuntimeURL() throws -> URL {
        let root = packageRoot()
        let candidates = [
            root.appendingPathComponent(".build/arm64-apple-macosx/debug/codex"),
            root.appendingPathComponent(".build/debug/codex"),
        ]
        if let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return executable
        }
        throw IntegrationHarnessError.missingExecutable(candidates.map(\.path).joined(separator: ", "))
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class EventRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.codex.xpcbridge.tests.recorder")
    private var events: [RuntimeEventEnvelope] = []

    func append(_ event: RuntimeEventEnvelope) {
        queue.sync {
            events.append(event)
        }
    }

    func kinds() -> [RuntimeEventKind] {
        queue.sync {
            events.map(\.kind)
        }
    }

    func completedToolResults() throws -> [ToolResultPayload] {
        try queue.sync {
            try events
                .filter { $0.kind == .toolCallCompleted }
                .map { try $0.decodePayload(ToolResultPayload.self) }
        }
    }

    func failedToolResults() -> [ToolResultPayload] {
        queue.sync {
            events
                .filter { $0.kind == .toolCallFailed }
                .compactMap { try? $0.decodePayload(ToolResultPayload.self) }
        }
    }

    func waitForKind(_ kind: RuntimeEventKind, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let hasKind = queue.sync {
                events.contains(where: { $0.kind == kind })
            }
            if hasKind {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw IntegrationHarnessError.timeout("event \(kind.rawValue)")
    }

    func waitForApproval(toolName: ToolID, timeout: TimeInterval = 5) async throws -> PendingApprovalRecord {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let approval = queue.sync {
                events
                    .filter({ $0.kind == .approvalRequired })
                    .compactMap({ try? $0.decodePayload(ApprovalRequiredPayload.self) })
                    .first(where: { $0.toolName == toolName })
            }
            if let approval {
                return PendingApprovalRecord(id: approval.toolInvocationId, toolName: approval.toolName)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw IntegrationHarnessError.timeout("approval \(toolName.rawValue)")
    }

    func waitForToolRequest(toolName: ToolID, timeout: TimeInterval = 5) async throws -> ToolCallPayload {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let toolRequest = queue.sync {
                events
                    .filter({ $0.kind == .toolCallRequested })
                    .compactMap({ try? $0.decodePayload(ToolCallPayload.self) })
                    .last(where: { $0.toolName == toolName })
            }
            if let toolRequest {
                return toolRequest
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw IntegrationHarnessError.timeout("tool request \(toolName.rawValue)")
    }

    func waitForCompletion(timeout: TimeInterval = 5) async throws -> CompletionPayload {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let completion = queue.sync {
                events
                    .filter({ $0.kind == .assistantMessageCompleted })
                    .compactMap({ try? $0.decodePayload(CompletionPayload.self) })
                    .last
            }
            if let completion {
                return completion
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw IntegrationHarnessError.timeout("completion")
    }

    func waitForWarning(timeout: TimeInterval = 5) async throws -> RuntimeErrorPayload {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let warning = queue.sync {
                events
                    .filter({ $0.kind == .runtimeWarning })
                    .compactMap({ try? $0.decodePayload(RuntimeErrorPayload.self) })
                    .last
            }
            if let warning {
                return warning
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw IntegrationHarnessError.timeout("warning")
    }

    func waitForWarning(code: String, timeout: TimeInterval = 5) async throws -> RuntimeErrorPayload {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let warning = queue.sync {
                events
                    .filter({ $0.kind == .runtimeWarning })
                    .compactMap({ try? $0.decodePayload(RuntimeErrorPayload.self) })
                    .last(where: { $0.code == code })
            }
            if let warning {
                return warning
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw IntegrationHarnessError.timeout("warning \(code)")
    }

    func waitForRuntimeError(code: String, timeout: TimeInterval = 5) async throws -> RuntimeErrorPayload {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let error = queue.sync {
                events
                    .filter({ $0.kind == .runtimeError })
                    .compactMap({ try? $0.decodePayload(RuntimeErrorPayload.self) })
                    .last(where: { $0.code == code })
            }
            if let error {
                return error
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw IntegrationHarnessError.timeout("runtime error \(code)")
    }
}

private struct PendingApprovalRecord {
    let id: String
    let toolName: ToolID
}

private enum IntegrationHarnessError: LocalizedError {
    case timeout(String)
    case missingExecutable(String)
    case invalidFixture(String)

    var errorDescription: String? {
        switch self {
        case let .timeout(label):
            return "Timed out waiting for \(label)"
        case let .missingExecutable(path):
            return "Missing bundled runtime executable at \(path)"
        case let .invalidFixture(message):
            return message
        }
    }
}
