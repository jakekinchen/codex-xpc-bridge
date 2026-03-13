import Foundation
import CodexBridgeContract

public protocol ToolApprovalPolicy: Sendable {
    func requiresExplicitApproval(for tool: ToolID) -> Bool
}

public struct ApprovalPolicy: ToolApprovalPolicy {
    public static let defaultAllowedWithoutApproval: Set<ToolID> = [
        DemoToolID.importShader,
        DemoToolID.validateShader,
        DemoToolID.capturePreview,
        DemoToolID.saveStyleProfile,
        DemoToolID.readWorkspaceFile,
        DemoToolID.writeWorkspaceFile,
    ]

    private let allowedWithoutApproval: Set<ToolID>

    public init(allowedWithoutApproval: Set<ToolID> = Self.defaultAllowedWithoutApproval) {
        self.allowedWithoutApproval = allowedWithoutApproval
    }

    public func requiresExplicitApproval(for tool: ToolID) -> Bool {
        !allowedWithoutApproval.contains(tool)
    }

    public static func requiresExplicitApproval(for tool: ToolID) -> Bool {
        ApprovalPolicy().requiresExplicitApproval(for: tool)
    }
}
