import XCTest
@testable import CodexBridgeContract
@testable import CodexBridgeServiceCore

final class ApprovalPolicyTests: XCTestCase {
    func testApprovalPolicyIsClosedAndExplicit() {
        XCTAssertTrue(ApprovalPolicy.requiresExplicitApproval(for: DemoToolID.convertShader))
        XCTAssertTrue(ApprovalPolicy.requiresExplicitApproval(for: DemoToolID.saveToLibrary))
        XCTAssertFalse(ApprovalPolicy.requiresExplicitApproval(for: DemoToolID.writeWorkspaceFile))
        XCTAssertFalse(ApprovalPolicy.requiresExplicitApproval(for: DemoToolID.validateShader))
        XCTAssertFalse(ApprovalPolicy.requiresExplicitApproval(for: DemoToolID.saveStyleProfile))
    }
}
