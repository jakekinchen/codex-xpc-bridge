import Foundation

public enum CodexBridgeRelayConfiguration {
    public static let serviceIdentifierEnvironmentKey = "CODEX_XPC_BRIDGE_SERVICE_IDENTIFIER"
    public static let serviceIdentifierInfoKey = "CodexXPCBridgeServiceIdentifier"
    public static let fallbackServiceIdentifier = "dev.codex.xpcbridge.demo.CodexXPCBridgeService"

    public static func resolveServiceIdentifier(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> String {
        if let configured = normalized(environment[serviceIdentifierEnvironmentKey]) {
            return configured
        }
        if let configured = normalized(infoDictionary[serviceIdentifierInfoKey] as? String) {
            return configured
        }
        return fallbackServiceIdentifier
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
