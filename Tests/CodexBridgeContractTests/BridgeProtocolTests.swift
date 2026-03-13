import XCTest
@testable import CodexBridgeContract

final class BridgeProtocolTests: XCTestCase {
    func testRequestEnvelopeRoundTripsPromptPayload() throws {
        let envelope = try RuntimeRequestEnvelope.make(
            sessionId: "session-1",
            conversationId: "conversation-1",
            kind: .sendPrompt,
            payload: PromptSubmission(prompt: "Convert this shader")
        )

        let data = try JSONLineCodec.encodeLine(envelope)
        let decoded = try JSONLineCodec.decode(RuntimeRequestEnvelope.self, from: data)
        let decodedPayload = try decoded.decodePayload(PromptSubmission.self)

        XCTAssertEqual(decoded.kind, .sendPrompt)
        XCTAssertEqual(decodedPayload.prompt, "Convert this shader")
    }

    func testToolPayloadRoundTripsWithArguments() throws {
        let toolPayload = ToolCallPayload(
            toolInvocationId: "convert-1",
            toolName: DemoToolID.convertShader,
            summary: "Convert shader",
            requiresApproval: true,
            arguments: ["sourcePath": .string("Drafts/input.glsl")]
        )

        let envelope = try RuntimeEventEnvelope.make(sessionId: "session-1", kind: .toolCallRequested, payload: toolPayload)
        let decoded = try JSONLineCodec.decode(RuntimeEventEnvelope.self, from: JSONLineCodec.encodeLine(envelope))
        let decodedPayload = try decoded.decodePayload(ToolCallPayload.self)

        XCTAssertEqual(decodedPayload.toolInvocationId, "convert-1")
        XCTAssertEqual(decodedPayload.toolName, DemoToolID.convertShader)
        XCTAssertTrue(decodedPayload.requiresApproval)
        XCTAssertEqual(decodedPayload.arguments["sourcePath"], .string("Drafts/input.glsl"))
    }
}
