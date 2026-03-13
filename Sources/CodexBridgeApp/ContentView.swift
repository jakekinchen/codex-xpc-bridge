import SwiftUI
import CodexBridgeSupport

struct ContentView: View {
    @ObservedObject var model: AppViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.96, green: 0.91, blue: 0.83), Color(red: 0.90, green: 0.94, blue: 0.97)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                header
                HStack(alignment: .top, spacing: 18) {
                    transcriptPanel
                    sidebar
                }
                composer
            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CodexXPCBridgeDemo")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Generic MAS-safe app shell for a private XPC bridge and bundled Codex runtime.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(model.state.status.badgeLabel, systemImage: "bolt.horizontal.circle.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(statusTint.opacity(0.18), in: Capsule())
                .foregroundStyle(statusTint)

            VStack(alignment: .leading, spacing: 4) {
                Text("Provider")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(model.providerStatus)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }

            Button("Cancel Turn") { Task { await model.cancelTurn() } }
                .buttonStyle(.bordered)
            Button("Reset Session") { Task { await model.resetSession() } }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.20, green: 0.31, blue: 0.58))
        }
        .padding(20)
        .panelBackground()
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Transcript")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Text(model.latestDiagnostic)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.state.transcript) { item in
                        TranscriptCard(item: item)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 420)
        .padding(20)
        .panelBackground()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            QuickActionsCard(activeScenario: $model.activeScenario) { scenario in
                Task { await model.runScenario(scenario) }
            }
            ApprovalDeckView(
                approval: model.state.pendingApproval,
                onApprove: { Task { await model.approvePending() } },
                onReject: { Task { await model.rejectPending() } }
            )
            ArtifactListView(artifacts: model.state.artifactPaths)
        }
        .frame(width: 340)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Prompt")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer()
                Text("Session \(model.sessionId.prefix(8))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $model.promptText)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .frame(minHeight: 110)
                .padding(12)
                .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1))

            HStack {
                Text("Use the quick actions to exercise conversion, validation, preview, library save, and style memory flows.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Send Prompt") { Task { await model.sendPrompt() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.84, green: 0.36, blue: 0.16))
            }
        }
        .padding(20)
        .panelBackground()
    }

    private var statusTint: Color {
        switch model.state.status {
        case .disconnected, .stopped: return .gray
        case .starting: return .orange
        case .ready: return .green
        case .busy: return .blue
        case .waitingForApproval: return .orange
        case .interrupted: return .yellow
        case .failed: return .red
        }
    }
}

private struct TranscriptCard: View {
    let item: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.role.rawValue.uppercased())
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(kindColor.opacity(0.16), in: Capsule())
                    .foregroundStyle(kindColor)
                Spacer()
            }
            Text(item.text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .textSelection(.enabled)
        }
        .padding(16)
        .background(.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(kindColor.opacity(0.22), lineWidth: 1))
    }

    private var kindColor: Color {
        switch item.role {
        case .system: return .indigo
        case .user: return .blue
        case .assistant: return .green
        case .tool: return .orange
        case .warning: return .yellow
        case .error: return .red
        }
    }
}

private struct QuickActionsCard: View {
    @Binding var activeScenario: DemoScenario
    let onRun: (DemoScenario) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick actions")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text("These prompts are designed to exercise the bounded MAS tool surface.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            ForEach(DemoScenario.allCases) { scenario in
                Button {
                    activeScenario = scenario
                    onRun(scenario)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scenario.rawValue)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Text(scenario.prompt)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(activeScenario == scenario ? 0.92 : 0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .panelBackground()
    }
}

private struct ApprovalDeckView: View {
    let approval: PendingApproval?
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Approvals")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer()
                Text(approval == nil ? "0" : "1")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.18), in: Capsule())
            }

            if let approval {
                VStack(alignment: .leading, spacing: 10) {
                    Text(approval.toolName.rawValue)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    Text(approval.reason)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                    Text(approval.summary)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Reject") { onReject() }
                            .buttonStyle(.bordered)
                        Button("Approve") { onApprove() }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.16, green: 0.50, blue: 0.28))
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Text("No active approvals. The XPC service will surface tool decisions here when policy requires a user decision.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .panelBackground()
    }
}

private struct ArtifactListView: View {
    let artifacts: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Artifacts")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer()
                Text("\(artifacts.count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.18), in: Capsule())
            }

            if artifacts.isEmpty {
                Text("Converted WGSL files, validation reports, previews, and saved library outputs appear here as tool results arrive.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(artifacts, id: \.self) { artifact in
                    Text(artifact)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(18)
        .panelBackground()
    }
}

private extension View {
    func panelBackground() -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 12)
    }
}
