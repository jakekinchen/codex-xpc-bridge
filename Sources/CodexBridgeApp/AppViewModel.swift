import Foundation
import CodexBridgeContract
import CodexBridgeSupport

@MainActor
final class AppViewModel: ObservableObject {
    @Published var state = BridgeSessionState(
        transcript: [
            TranscriptEntry(role: .system, text: "A generic MAS-safe bridge shell for app -> XPC -> codex over stdio.")
        ]
    )
    @Published var promptText = ""
    @Published var providerStatus = "Not connected"
    @Published var latestDiagnostic = "No diagnostics yet"
    @Published var activeScenario: DemoScenario = .pipeline
    @Published var sessionId = UUID().uuidString
    @Published var conversationId = UUID().uuidString

    private let client = CodexXPCClient()
    private var bootstrapped = false

    init() {
        client.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    func bootstrapIfNeeded() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        state.status = .starting
        state.statusDetail = "Connecting"
        do {
            _ = try await client.send(.make(sessionId: sessionId, conversationId: conversationId, kind: .createSession, payload: SessionCreatePayload(conversationTitle: "Codex Bridge Demo")))
            _ = try await client.send(RuntimeRequestEnvelope(sessionId: sessionId, conversationId: conversationId, kind: .queryRuntimeStatus))
        } catch {
            state.status = .failed
            state.statusDetail = error.localizedDescription
            state.transcript.append(TranscriptEntry(role: .error, text: error.localizedDescription))
        }
    }

    func sendPrompt() async {
        let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.transcript.append(SessionStore.makeUserEntry(prompt: trimmed))
        promptText = ""
        do {
            _ = try await client.send(.make(sessionId: sessionId, conversationId: conversationId, kind: .sendPrompt, payload: PromptSubmission(prompt: trimmed)))
        } catch {
            state.status = .failed
            state.statusDetail = error.localizedDescription
            state.transcript.append(TranscriptEntry(role: .error, text: error.localizedDescription))
        }
    }

    func runScenario(_ scenario: DemoScenario) async {
        activeScenario = scenario
        promptText = scenario.prompt
        await sendPrompt()
    }

    func approvePending() async {
        guard let approval = state.pendingApproval else { return }
        do {
            _ = try await client.send(.make(sessionId: sessionId, conversationId: conversationId, kind: .resolveApproval, payload: ApprovalResolutionPayload(toolInvocationId: approval.id, decision: .approve)))
        } catch {
            state.status = .failed
            state.transcript.append(TranscriptEntry(role: .error, text: error.localizedDescription))
        }
    }

    func rejectPending() async {
        guard let approval = state.pendingApproval else { return }
        do {
            _ = try await client.send(.make(sessionId: sessionId, conversationId: conversationId, kind: .resolveApproval, payload: ApprovalResolutionPayload(toolInvocationId: approval.id, decision: .reject)))
        } catch {
            state.status = .failed
            state.transcript.append(TranscriptEntry(role: .error, text: error.localizedDescription))
        }
    }

    func cancelTurn() async {
        do {
            _ = try await client.send(RuntimeRequestEnvelope(sessionId: sessionId, conversationId: conversationId, kind: .cancelOperation))
        } catch {
            state.status = .failed
            state.transcript.append(TranscriptEntry(role: .error, text: error.localizedDescription))
        }
    }

    func resetSession() async {
        do {
            _ = try await client.send(RuntimeRequestEnvelope(sessionId: sessionId, conversationId: conversationId, kind: .terminateSession))
        } catch {
            state.transcript.append(TranscriptEntry(role: .warning, text: error.localizedDescription))
        }

        sessionId = UUID().uuidString
        conversationId = UUID().uuidString
        state = BridgeSessionState(transcript: [TranscriptEntry(role: .system, text: "Created a fresh logical session identifier for the next run.")])
        providerStatus = "Not connected"
        latestDiagnostic = "Session reset"
        bootstrapped = false
        await bootstrapIfNeeded()
    }

    private func handle(_ event: RuntimeEventEnvelope) {
        latestDiagnostic = "\(event.kind.rawValue) @ \(event.timestamp.formatted(date: .omitted, time: .standard))"
        if let payload = try? event.decodePayload(RuntimeStatusPayload.self), event.kind == .providerStatus || event.kind == .runtimeStatus {
            providerStatus = payload.detail ?? payload.state.badgeLabel
        }
        SessionStore.reduce(&state, event: event)
    }
}
