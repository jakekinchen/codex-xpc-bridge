import XCTest
@testable import CodexBridgeRelaySupport

final class CodexBridgeRelayConfigurationTests: XCTestCase {
    func testResolveServiceIdentifierPrefersEnvironmentOverride() {
        let resolved = CodexBridgeRelayConfiguration.resolveServiceIdentifier(
            environment: [
                CodexBridgeRelayConfiguration.serviceIdentifierEnvironmentKey: "com.example.env-bridge"
            ],
            infoDictionary: [
                CodexBridgeRelayConfiguration.serviceIdentifierInfoKey: "com.example.bundle-bridge"
            ]
        )

        XCTAssertEqual(resolved, "com.example.env-bridge")
    }

    func testResolveServiceIdentifierFallsBackToInfoDictionary() {
        let resolved = CodexBridgeRelayConfiguration.resolveServiceIdentifier(
            environment: [:],
            infoDictionary: [
                CodexBridgeRelayConfiguration.serviceIdentifierInfoKey: "com.example.bundle-bridge"
            ]
        )

        XCTAssertEqual(resolved, "com.example.bundle-bridge")
    }

    func testResolveServiceIdentifierFallsBackToDefaultIdentifier() {
        let resolved = CodexBridgeRelayConfiguration.resolveServiceIdentifier(
            environment: [:],
            infoDictionary: [:]
        )

        XCTAssertEqual(resolved, CodexBridgeRelayConfiguration.fallbackServiceIdentifier)
    }
}
