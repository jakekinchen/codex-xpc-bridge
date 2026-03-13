import Foundation

public actor DiagnosticsRecorder {
    private let logsRoot: URL
    private let fileManager: FileManager

    public init(logsRoot: URL, fileManager: FileManager = .default) {
        self.logsRoot = logsRoot
        self.fileManager = fileManager
    }

    public func record(_ message: String, fileName: String = "runtime-service.log") async {
        do {
            try fileManager.createDirectory(at: logsRoot, withIntermediateDirectories: true)
            let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(Self.redact(message))\n"
            let target = logsRoot.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: target.path) {
                let handle = try FileHandle(forWritingTo: target)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try Data(line.utf8).write(to: target)
            }
        } catch {
        }
    }

    public func append(_ message: String, to fileName: String) async {
        await record(message, fileName: fileName)
    }

    public static func redact(_ message: String) -> String {
        message
            .replacingOccurrences(of: "sk-", with: "sk-REDACTED-")
            .replacingOccurrences(of: "Bearer ", with: "Bearer REDACTED-")
    }
}
