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

        let firstApproval = try await recorder.waitForApproval(idPrefix: "convert")
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .resolveApproval, payload: ApprovalResolutionPayload(toolInvocationId: firstApproval.id, decision: .approve)))

        let secondApproval = try await recorder.waitForApproval(idPrefix: "save")
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .resolveApproval, payload: ApprovalResolutionPayload(toolInvocationId: secondApproval.id, decision: .approve)))

        let completion = try await recorder.waitForCompletion()
        XCTAssertEqual(completion.finalText, "Completed bounded pipeline.")

        let completedResults = try recorder.completedToolResults()
        XCTAssertEqual(completedResults.map(\.toolName), [.writeWorkspaceFile, .convertShader, .validateShader, .capturePreview, .saveToLibrary])
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

        let firstApproval = try await recorder.waitForApproval(idPrefix: "convert")
        _ = try await broker.handle(.make(sessionId: sessionId, kind: .resolveApproval, payload: ApprovalResolutionPayload(toolInvocationId: firstApproval.id, decision: .reject)))

        let completion = try await recorder.waitForCompletion()
        XCTAssertEqual(completion.finalText, "Flow stopped after rejected or failed tool.")

        let completedResults = try recorder.completedToolResults()
        XCTAssertEqual(completedResults.map(\.toolName), [.writeWorkspaceFile])

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

    private func makeBroker(recorder: EventRecorder) throws -> CodexSessionBroker {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-xpc-bridge-integration", isDirectory: true)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        let resolver = RuntimePathResolver(environment: ["CODEX_BRIDGE_ROOT": root.path])
        return try CodexSessionBroker(
            pathResolver: resolver,
            binaryLocator: RuntimeBinaryLocator(environment: [:], bundledCandidates: [try bundledRuntimeURL()])
        ) { event in
            recorder.append(event)
        }
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

    func waitForApproval(idPrefix: String, timeout: TimeInterval = 5) async throws -> PendingApprovalRecord {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let approval = queue.sync {
                events
                    .filter({ $0.kind == .approvalRequired })
                    .compactMap({ try? $0.decodePayload(ApprovalRequiredPayload.self) })
                    .first(where: { $0.toolInvocationId.hasPrefix(idPrefix) })
            }
            if let approval {
                return PendingApprovalRecord(id: approval.toolInvocationId, toolName: approval.toolName)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw IntegrationHarnessError.timeout("approval \(idPrefix)")
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
}

private struct PendingApprovalRecord {
    let id: String
    let toolName: ToolName
}

private enum IntegrationHarnessError: LocalizedError {
    case timeout(String)
    case missingExecutable(String)

    var errorDescription: String? {
        switch self {
        case let .timeout(label):
            return "Timed out waiting for \(label)"
        case let .missingExecutable(path):
            return "Missing bundled runtime executable at \(path)"
        }
    }
}
