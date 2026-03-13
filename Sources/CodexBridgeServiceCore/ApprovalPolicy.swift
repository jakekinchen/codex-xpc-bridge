import Foundation
import CodexBridgeContract

public enum ApprovalPolicy {
    public static func requiresExplicitApproval(for tool: ToolName) -> Bool {
        switch tool {
        case .convertShader, .saveToLibrary:
            return true
        case .importShader, .validateShader, .capturePreview, .saveStyleProfile, .readWorkspaceFile, .writeWorkspaceFile:
            return false
        }
    }
}
