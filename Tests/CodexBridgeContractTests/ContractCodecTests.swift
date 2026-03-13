import XCTest
@testable import CodexBridgeContract

final class ContractCodecTests: XCTestCase {
    func testJSONValueSupportsNestedObjects() throws {
        let payload: [String: AnyEncodable] = [
            "ok": AnyEncodable(true),
            "count": AnyEncodable(2),
            "meta": AnyEncodable(["kind": AnyEncodable("wgsl")]),
        ]
        let value = try PayloadCoder.encode(payload)
        guard case .object(let object) = value else {
            return XCTFail("Expected object payload")
        }
        XCTAssertEqual(object["ok"], .bool(true))
        XCTAssertEqual(object["count"], .number(2))
        XCTAssertEqual(object["meta"]?.objectValue?["kind"], .string("wgsl"))
    }

    func testToolResultPayloadRoundTripsOutputsAndArtifacts() throws {
        let payload = ToolResultPayload(
            toolInvocationId: "validate-1",
            toolName: .validateShader,
            success: true,
            summary: "Validation passed.",
            outputs: ["report": .string("diagnostics/report.json")],
            artifactPaths: ["/tmp/report.json"]
        )

        let event = try RuntimeEventEnvelope.make(sessionId: "session-1", kind: .toolCallCompleted, payload: payload)
        let decoded = try JSONLineCodec.decode(RuntimeEventEnvelope.self, from: JSONLineCodec.encode(event))
        let result = try decoded.decodePayload(ToolResultPayload.self)

        XCTAssertEqual(result.toolInvocationId, "validate-1")
        XCTAssertEqual(result.outputs["report"], .string("diagnostics/report.json"))
        XCTAssertEqual(result.artifactPaths, ["/tmp/report.json"])
    }
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self.encodeClosure = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
