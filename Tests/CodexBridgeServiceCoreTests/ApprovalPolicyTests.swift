import XCTest
@testable import CodexBridgeContract
@testable import CodexBridgeServiceCore

final class ApprovalPolicyTests: XCTestCase {
    func testApprovalPolicyIsClosedAndExplicit() {
        XCTAssertTrue(ApprovalPolicy.requiresExplicitApproval(for: .convertShader))
        XCTAssertTrue(ApprovalPolicy.requiresExplicitApproval(for: .saveToLibrary))
        XCTAssertFalse(ApprovalPolicy.requiresExplicitApproval(for: .writeWorkspaceFile))
        XCTAssertFalse(ApprovalPolicy.requiresExplicitApproval(for: .validateShader))
        XCTAssertFalse(ApprovalPolicy.requiresExplicitApproval(for: .saveStyleProfile))
    }
}
