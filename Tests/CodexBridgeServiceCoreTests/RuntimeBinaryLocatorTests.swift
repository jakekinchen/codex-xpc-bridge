import XCTest
@testable import CodexBridgeServiceCore

final class RuntimeBinaryLocatorTests: XCTestCase {
    func testPrefersEnvironmentOverrideWhenExecutableExists() throws {
        let fileManager = FileManager.default
        let temp = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: temp)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.path)

        let locator = RuntimeBinaryLocator(environment: ["CODEX_BRIDGE_CODEX_BINARY": temp.path], bundledCandidates: [])

        XCTAssertEqual(try locator.locate(), temp)
    }

    func testFallsBackToBundledCandidates() throws {
        let fileManager = FileManager.default
        let temp = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: temp)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.path)

        let locator = RuntimeBinaryLocator(environment: [:], bundledCandidates: [temp])

        XCTAssertEqual(try locator.locate(), temp)
    }
}
