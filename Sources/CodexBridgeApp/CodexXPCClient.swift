import Foundation
import CodexBridgeContract
import CodexBridgeXPC

@MainActor
final class CodexXPCClient: NSObject, CodexBridgeClientXPCProtocol {
    var onEvent: ((RuntimeEventEnvelope) -> Void)?
    private var connection: NSXPCConnection?

    private var serviceIdentifier: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: CodexBridgeServiceInfo.serviceIdentifierKey) as? String, !configured.isEmpty {
            return configured
        }
        return "dev.codex.xpcbridge.demo.CodexXPCBridgeService"
    }

    func connectIfNeeded() {
        guard connection == nil else { return }
        let connection = NSXPCConnection(serviceName: serviceIdentifier)
        connection.remoteObjectInterface = NSXPCInterface(with: CodexBridgeServiceXPCProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: CodexBridgeClientXPCProtocol.self)
        connection.exportedObject = self
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.emitSynthetic(kind: .serviceInterrupted, message: "XPC connection interrupted.")
            }
        }
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.emitSynthetic(kind: .runtimeError, message: "XPC connection invalidated.")
            }
        }
        connection.resume()
        self.connection = connection
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }

    func send(_ request: RuntimeRequestEnvelope) async throws -> RuntimeReplyEnvelope {
        connectIfNeeded()
        guard let connection else {
            throw XPCErrorFactory.message("Missing XPC connection")
        }

        let data = try XPCEnvelopeCodec.encodeRequest(request)
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            }
            guard let service = proxy as? CodexBridgeServiceXPCProtocol else {
                continuation.resume(throwing: XPCErrorFactory.message("Remote XPC proxy mismatch"))
                return
            }
            service.send(data) { responseData, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let responseData else {
                    continuation.resume(throwing: XPCErrorFactory.message("XPC service returned no reply"))
                    return
                }
                do {
                    continuation.resume(returning: try XPCEnvelopeCodec.decodeResponse(responseData))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated func receiveEvent(_ eventData: Data) {
        Task { @MainActor in
            guard let event = try? XPCEnvelopeCodec.decodeEvent(eventData) else {
                emitSynthetic(kind: .runtimeWarning, message: "Received an unreadable event payload from the XPC service.")
                return
            }
            onEvent?(event)
        }
    }

    private func emitSynthetic(kind: RuntimeEventKind, message: String) {
        let event = RuntimeEventEnvelope(
            sessionId: "synthetic",
            kind: kind,
            payload: try? PayloadCoder.encode(RuntimeErrorPayload(code: kind.rawValue, message: message, retryable: true))
        )
        onEvent?(event)
    }
}
