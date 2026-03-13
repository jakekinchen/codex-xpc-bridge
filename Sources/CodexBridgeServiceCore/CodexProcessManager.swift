import Foundation
import CodexBridgeContract
import CodexBridgeSupport
import CodexBridgeXPC

public actor CodexProcessManager {
    public typealias EventHandler = @Sendable (RuntimeEventEnvelope) async -> Void
    public typealias TerminationHandler = @Sendable (String) async -> Void

    private let binaryURL: URL
    private let environment: [String: String]
    private let diagnostics: DiagnosticsRecorder
    private let eventHandler: EventHandler
    private let terminationHandler: TerminationHandler

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var forcedTerminationReason: String?
    private var stopping = false

    public init(
        binaryURL: URL,
        environment: [String: String],
        diagnostics: DiagnosticsRecorder,
        eventHandler: @escaping EventHandler,
        terminationHandler: @escaping TerminationHandler
    ) {
        self.binaryURL = binaryURL
        self.environment = environment
        self.diagnostics = diagnostics
        self.eventHandler = eventHandler
        self.terminationHandler = terminationHandler
    }

    public func start() throws {
        guard process == nil else { return }

        let process = Process()
        process.executableURL = binaryURL
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] process in
            Task {
                await self?.handleTermination(status: process.terminationStatus)
            }
        }

        try process.run()

        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutHandle = stdoutPipe.fileHandleForReading
        self.stderrHandle = stderrPipe.fileHandleForReading
        self.stopping = false

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.consumeStdout(data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.consumeStderr(data)
            }
        }
    }

    public func send(_ request: RuntimeRequestEnvelope) throws {
        guard let stdinHandle else {
            throw XPCErrorFactory.message("Codex process is not running")
        }
        try stdinHandle.write(contentsOf: JSONLineCodec.encodeLine(request))
    }

    public func stop(reason: String = "stopped") async {
        stopping = true
        forcedTerminationReason = reason
        await diagnostics.append("stopping codex process: \(reason)", to: "runtime-service.log")
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        stdinHandle?.closeFile()
        process?.terminate()
        process = nil
    }

    private func handleTermination(status: Int32) async {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        let reason = forcedTerminationReason ?? (stopping ? "stopped" : "exit_\(status)")
        forcedTerminationReason = nil
        await diagnostics.append("codex process terminated: \(reason)", to: "runtime-service.log")
        await terminationHandler(reason)
    }

    private func consumeStdout(_ data: Data) async {
        guard !data.isEmpty else { return }

        stdoutBuffer.append(data)
        while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer.prefix(upTo: newlineIndex)
            stdoutBuffer.removeSubrange(...newlineIndex)
            guard !line.isEmpty else { continue }

            do {
                let event = try JSONLineCodec.decode(RuntimeEventEnvelope.self, from: Data(line))
                await eventHandler(event)
            } catch {
                await diagnostics.append("stdout decode failure: \(error)", to: "runtime-service.log")
                forcedTerminationReason = "protocol_violation"
                stdoutHandle?.readabilityHandler = nil
                stderrHandle?.readabilityHandler = nil
                process?.terminate()
                return
            }
        }
    }

    private func consumeStderr(_ data: Data) async {
        guard !data.isEmpty else { return }

        stderrBuffer.append(data)
        while let newlineIndex = stderrBuffer.firstIndex(of: 0x0A) {
            let line = stderrBuffer.prefix(upTo: newlineIndex)
            stderrBuffer.removeSubrange(...newlineIndex)
            guard let message = String(data: line, encoding: .utf8), !message.isEmpty else { continue }
            await diagnostics.append("codex stderr: \(message)", to: "codex-stderr.log")
        }
    }
}
