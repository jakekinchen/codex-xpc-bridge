import Foundation
import CodexBridgeContract

@objc public protocol CodexBridgeServiceXPCProtocol {
    func send(_ requestData: Data, reply: @escaping (Data?, NSError?) -> Void)
    func shutdown(reply: @escaping (NSError?) -> Void)
}

@objc public protocol CodexBridgeClientXPCProtocol {
    func receiveEvent(_ eventData: Data)
}

public enum XPCErrorFactory {
    public static func make(_ error: Error, code: Int = 1) -> NSError {
        let nsError = error as NSError
        return NSError(domain: "dev.codex.xpcbridge.xpc", code: code, userInfo: [NSLocalizedDescriptionKey: nsError.localizedDescription])
    }

    public static func message(_ message: String, code: Int = 1) -> NSError {
        NSError(domain: "dev.codex.xpcbridge.xpc", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

public enum XPCEnvelopeCodec {
    public static func encodeRequest(_ envelope: RuntimeRequestEnvelope) throws -> Data {
        try JSONLineCodec.encode(envelope)
    }

    public static func decodeRequest(_ data: Data) throws -> RuntimeRequestEnvelope {
        try JSONLineCodec.decode(RuntimeRequestEnvelope.self, from: data)
    }

    public static func encodeResponse(_ envelope: RuntimeReplyEnvelope) throws -> Data {
        try JSONLineCodec.encode(envelope)
    }

    public static func decodeResponse(_ data: Data) throws -> RuntimeReplyEnvelope {
        try JSONLineCodec.decode(RuntimeReplyEnvelope.self, from: data)
    }

    public static func encodeEvent(_ envelope: RuntimeEventEnvelope) throws -> Data {
        try JSONLineCodec.encode(envelope)
    }

    public static func decodeEvent(_ data: Data) throws -> RuntimeEventEnvelope {
        try JSONLineCodec.decode(RuntimeEventEnvelope.self, from: data)
    }
}

public enum CodexBridgeServiceInfo {
    public static let serviceIdentifierKey = "CodexXPCBridgeServiceIdentifier"
}
