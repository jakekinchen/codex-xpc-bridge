import XCTest
@testable import CodexBridgeContract
@testable import CodexBridgeSupport

final class SessionStoreTests: XCTestCase {
    func testStreamingApprovalAndArtifactsFlowReducesIntoState() throws {
        var state = BridgeSessionState()

        let delta = try RuntimeEventEnvelope.make(sessionId: "session", kind: .assistantDelta, payload: AssistantDeltaPayload(text: "Hello "))
        let approval = try RuntimeEventEnvelope.make(
            sessionId: "session",
            kind: .approvalRequired,
            payload: ApprovalRequiredPayload(toolInvocationId: "convert-1", toolName: .convertShader, reason: "Needs approval", inputSummary: "drafts/demo-input.glsl")
        )
        let completedTool = try RuntimeEventEnvelope.make(
            sessionId: "session",
            kind: .toolCallCompleted,
            payload: ToolResultPayload(toolInvocationId: "convert-1", toolName: .convertShader, success: true, summary: "Converted.", artifactPaths: ["/tmp/demo-output.wgsl"])
        )
        let done = try RuntimeEventEnvelope.make(sessionId: "session", kind: .assistantMessageCompleted, payload: CompletionPayload(finalText: "Hello world"))

        SessionStore.reduce(&state, event: delta)
        SessionStore.reduce(&state, event: approval)
        SessionStore.reduce(&state, event: completedTool)
        SessionStore.reduce(&state, event: done)

        XCTAssertEqual(state.transcript.first(where: { $0.role == .assistant })?.text, "Hello world")
        XCTAssertEqual(state.pendingApproval?.id, "convert-1")
        XCTAssertEqual(state.artifactPaths, ["/tmp/demo-output.wgsl"])
        XCTAssertEqual(state.status, .ready)
    }
}
