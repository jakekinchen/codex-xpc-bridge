import XCTest
@testable import CodexBridgeContract
@testable import CodexBridgeServiceCore

final class ApprovalPolicyBehaviorTests: XCTestCase {
    func testUnknownToolsRequireApprovalByDefault() {
        let policy = ApprovalPolicy()
        let customTool: ToolID = "custom.host.tool"

        XCTAssertTrue(policy.requiresExplicitApproval(for: customTool))
    }

    func testAllowlistCanBeOverriddenByHostPolicyConfiguration() {
        let customTool: ToolID = "custom.host.tool"
        let policy = ApprovalPolicy(allowedWithoutApproval: [DemoToolID.validateShader, customTool])

        XCTAssertFalse(policy.requiresExplicitApproval(for: DemoToolID.validateShader))
        XCTAssertFalse(policy.requiresExplicitApproval(for: customTool))
        XCTAssertTrue(policy.requiresExplicitApproval(for: DemoToolID.convertShader))
    }
}
