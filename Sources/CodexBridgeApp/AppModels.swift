import Foundation
import CodexBridgeContract
import CodexBridgeSupport

enum DemoScenario: String, CaseIterable, Identifiable {
    case convert = "Convert sample shader"
    case pipeline = "Run full pipeline"
    case saveStyle = "Save style memory"
    case workspace = "Read workspace notes"

    var id: String { rawValue }

    var prompt: String {
        switch self {
        case .convert:
            return "Create a sample shader draft, convert it to WGSL, and summarize the output artifact."
        case .pipeline:
            return "Run the full bounded tool flow: write a sample workspace shader, convert it, validate it, capture a preview, and save it to the library."
        case .saveStyle:
            return "Remember this style profile as a warm sunrise gradient with soft grain and metal highlights."
        case .workspace:
            return "Read the latest workspace shader notes and explain what changed."
        }
    }
}

extension RuntimeStatusState {
    var badgeLabel: String {
        switch self {
        case .disconnected: return "Offline"
        case .starting: return "Starting"
        case .ready: return "Ready"
        case .busy: return "Running"
        case .waitingForApproval: return "Approval"
        case .interrupted: return "Interrupted"
        case .failed: return "Failed"
        case .stopped: return "Stopped"
        }
    }
}
