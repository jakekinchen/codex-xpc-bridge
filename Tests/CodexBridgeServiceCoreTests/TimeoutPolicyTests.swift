import XCTest
@testable import CodexBridgeServiceCore

final class TimeoutPolicyTests: XCTestCase {
    func testDefaultTimeoutPolicyMatchesPlanDefaults() {
        let policy = TimeoutPolicy()

        XCTAssertEqual(policy.startup, 5)
        XCTAssertEqual(policy.prompt, 60)
        XCTAssertEqual(policy.toolExecution, 30)
        XCTAssertEqual(policy.approval, 60)
        XCTAssertEqual(policy.childSilence, 60)
        XCTAssertEqual(policy.idleTeardown, 90)
    }

    func testTimeoutPolicySupportsHostOverrides() {
        let policy = TimeoutPolicy(
            startup: 1,
            prompt: 2,
            toolExecution: 3,
            approval: 4,
            childSilence: 5,
            idleTeardown: 6
        )

        XCTAssertEqual(policy.startup, 1)
        XCTAssertEqual(policy.prompt, 2)
        XCTAssertEqual(policy.toolExecution, 3)
        XCTAssertEqual(policy.approval, 4)
        XCTAssertEqual(policy.childSilence, 5)
        XCTAssertEqual(policy.idleTeardown, 6)
    }
}
