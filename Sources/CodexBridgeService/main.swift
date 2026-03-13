import Foundation
import CodexBridgeServiceCore
import CodexBridgeXPC

final class CodexBridgeServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: CodexBridgeServiceXPCProtocol.self)
        newConnection.remoteObjectInterface = NSXPCInterface(with: CodexBridgeClientXPCProtocol.self)

        let clientProxy = newConnection.remoteObjectProxyWithErrorHandler { error in
            NSLog("Client proxy error: %@", error.localizedDescription)
        } as? CodexBridgeClientXPCProtocol

        do {
            newConnection.exportedObject = try CodexBridgeConnectionHandler(client: clientProxy)
            newConnection.resume()
            return true
        } catch {
            NSLog("Failed to create connection handler: %@", error.localizedDescription)
            return false
        }
    }
}

let delegate = CodexBridgeServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
