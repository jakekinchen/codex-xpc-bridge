import XCTest
@testable import CodexBridgeServiceCore

final class RestartPolicyTests: XCTestCase {
    func testAllowsOnlyConfiguredRestartBudgetWithinWindow() {
        var policy = RestartPolicy(maxAutomaticRestarts: 1, window: 60)
        XCTAssertTrue(policy.registerCrash(at: Date(timeIntervalSince1970: 100)))
        XCTAssertFalse(policy.registerCrash(at: Date(timeIntervalSince1970: 120)))
        policy.reset()
        XCTAssertTrue(policy.registerCrash(at: Date(timeIntervalSince1970: 200)))
    }
}
