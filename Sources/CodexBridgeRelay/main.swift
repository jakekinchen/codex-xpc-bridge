import Darwin
import Foundation
import CodexBridgeContract
import CodexBridgeRelaySupport
import CodexBridgeXPC

actor RelayOutputWriter {
    private let stdoutHandle = FileHandle.standardOutput
    private let stderrHandle = FileHandle.standardError

    func writeReply(_ reply: RuntimeReplyEnvelope) throws {
        try stdoutHandle.write(contentsOf: JSONLineCodec.encode(reply))
    }

    func writeEvent(_ event: RuntimeEventEnvelope) throws {
        try stdoutHandle.write(contentsOf: JSONLineCodec.encode(event))
    }

    func logError(_ message: String) {
        guard let data = "\(message)\n".data(using: .utf8) else {
            return
        }
        try? stderrHandle.write(contentsOf: data)
    }
}

final class RelayXPCClient: NSObject, CodexBridgeClientXPCProtocol {
    private let serviceIdentifier: String
    private let writer: RelayOutputWriter
    private var connection: NSXPCConnection?

    init(serviceIdentifier: String, writer: RelayOutputWriter) {
        self.serviceIdentifier = serviceIdentifier
        self.writer = writer
        super.init()
    }

    func send(_ request: RuntimeRequestEnvelope) async throws -> RuntimeReplyEnvelope {
        connectIfNeeded()
        guard let connection else {
            throw XPCErrorFactory.message("Missing XPC connection to \(serviceIdentifier)")
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

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }

    nonisolated func receiveEvent(_ eventData: Data) {
        let writer = self.writer
        Task {
            do {
                let event = try XPCEnvelopeCodec.decodeEvent(eventData)
                try await writer.writeEvent(event)
            } catch {
                await writer.logError(
                    "Codex bridge relay failed to decode an event from the XPC service: \(error.localizedDescription)"
                )
            }
        }
    }

    private func connectIfNeeded() {
        guard connection == nil else { return }

        let connection = NSXPCConnection(serviceName: serviceIdentifier)
        connection.remoteObjectInterface = NSXPCInterface(with: CodexBridgeServiceXPCProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: CodexBridgeClientXPCProtocol.self)
        connection.exportedObject = self
        connection.interruptionHandler = { [writer] in
            Task {
                await writer.logError("Codex bridge relay XPC connection interrupted.")
            }
        }
        connection.invalidationHandler = { [weak self, writer] in
            Task {
                await writer.logError("Codex bridge relay XPC connection invalidated.")
            }
            self?.connection = nil
        }
        connection.resume()
        self.connection = connection
    }
}

@main
enum CodexBridgeRelayMain {
    static func main() async {
        let writer = RelayOutputWriter()
        let serviceIdentifier = CodexBridgeRelayConfiguration.resolveServiceIdentifier()
        let client = RelayXPCClient(serviceIdentifier: serviceIdentifier, writer: writer)

        do {
            try await run(client: client, writer: writer)
        } catch {
            await writer.logError("Codex bridge relay failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func run(client: RelayXPCClient, writer: RelayOutputWriter) async throws {
        defer {
            client.disconnect()
        }

        for try await line in FileHandle.standardInput.bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            guard let requestData = trimmed.data(using: .utf8) else {
                await writer.logError("Codex bridge relay could not encode an incoming stdin line as UTF-8.")
                continue
            }

            let request: RuntimeRequestEnvelope
            do {
                request = try JSONLineCodec.decode(RuntimeRequestEnvelope.self, from: requestData)
            } catch {
                await writer.logError(
                    "Codex bridge relay received an invalid request envelope: \(error.localizedDescription)"
                )
                continue
            }

            do {
                let reply = try await client.send(request)
                try await writer.writeReply(reply)
            } catch {
                try await writer.writeReply(
                    RuntimeReplyEnvelope(
                        requestId: request.requestId,
                        accepted: false,
                        message: error.localizedDescription
                    )
                )
            }
        }
    }
}
