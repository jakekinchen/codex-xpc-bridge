import Foundation

public enum RuntimeBinaryLocatorError: Error, Equatable {
    case notFound
}

public struct RuntimeBinaryLocator: @unchecked Sendable {
    private let environment: [String: String]
    private let bundledCandidates: [URL]
    private let fileManager: FileManager

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundledCandidates: [URL] = [],
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.bundledCandidates = bundledCandidates
        self.fileManager = fileManager
    }

    public func locate(bundle: Bundle = .main) throws -> URL {
        let candidates = candidateURLs(bundle: bundle)
        for candidate in candidates where candidate.isFileURL {
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw RuntimeBinaryLocatorError.notFound
    }

    public func candidateURLs(bundle: Bundle = .main) -> [URL] {
        var candidates: [URL] = []
        if let override = environment["CODEX_BRIDGE_CODEX_BINARY"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }
        candidates.append(contentsOf: bundledCandidates)
        if let resourceURL = bundle.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("codex"))
        }
        candidates.append(bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("Resources/codex"))
        candidates.append(bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/codex"))
        return candidates
    }
}

public typealias CodexBridgeRuntimeBinaryLocator = RuntimeBinaryLocator
public typealias CodexBridgeRuntimeBinaryLocatorError = RuntimeBinaryLocatorError
