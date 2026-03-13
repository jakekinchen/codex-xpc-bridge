import Foundation
import CodexBridgeContract
import CodexBridgeXPC

private final class ClientForwarder: @unchecked Sendable {
    weak var client: (any CodexBridgeClientXPCProtocol)?

    init(client: (any CodexBridgeClientXPCProtocol)?) {
        self.client = client
    }

    func forward(event: RuntimeEventEnvelope) {
        guard let client else { return }
        do {
            try client.receiveEvent(XPCEnvelopeCodec.encodeEvent(event))
        } catch {
            NSLog("Failed to send event to app: %@", error.localizedDescription)
        }
    }
}

private struct SendReplyBox: @unchecked Sendable {
    let reply: (Data?, NSError?) -> Void

    func call(_ data: Data?, _ error: NSError?) {
        reply(data, error)
    }
}

private struct ShutdownReplyBox: @unchecked Sendable {
    let reply: (NSError?) -> Void

    func call(_ error: NSError?) {
        reply(error)
    }
}

public final class CodexBridgeConnectionHandler: NSObject, CodexBridgeServiceXPCProtocol, @unchecked Sendable {
    private let broker: CodexSessionBroker
    private let clientForwarder: ClientForwarder

    public init(client: (any CodexBridgeClientXPCProtocol)?) throws {
        let forwarder = ClientForwarder(client: client)
        self.clientForwarder = forwarder
        self.broker = try CodexSessionBroker { event in
            forwarder.forward(event: event)
        }
        super.init()
    }

    public func send(_ requestData: Data, reply: @escaping (Data?, NSError?) -> Void) {
        let replyBox = SendReplyBox(reply: reply)
        Task {
            do {
                let request = try XPCEnvelopeCodec.decodeRequest(requestData)
                let response = try await broker.handle(request)
                replyBox.call(try XPCEnvelopeCodec.encodeResponse(response), nil)
            } catch {
                replyBox.call(nil, XPCErrorFactory.make(error))
            }
        }
    }

    public func shutdown(reply: @escaping (NSError?) -> Void) {
        let replyBox = ShutdownReplyBox(reply: reply)
        Task {
            await broker.shutdown()
            replyBox.call(nil)
        }
    }
}
