import Foundation

public struct RuntimePaths: Sendable, Equatable {
    public let root: URL
    public let codexHome: URL
    public let workspaceRoot: URL
    public let importsRoot: URL
    public let libraryRoot: URL
    public let styleMemoryRoot: URL
    public let logsRoot: URL
    public let diagnosticsRoot: URL
}

public typealias CodexBridgePaths = RuntimePaths

public enum RuntimePathResolverError: Error, LocalizedError {
    case absolutePathRejected(String)
    case pathTraversalRejected(String)
    case pathEscapedRoot(String)
    case invalidRelativePath(String)

    public var errorDescription: String? {
        switch self {
        case .absolutePathRejected(let path):
            return "Absolute path rejected: \(path)"
        case .pathTraversalRejected(let path):
            return "Path traversal rejected: \(path)"
        case .pathEscapedRoot(let path):
            return "Path escaped approved root: \(path)"
        case .invalidRelativePath(let path):
            return "Invalid relative path: \(path)"
        }
    }
}

public struct RuntimePathResolver: @unchecked Sendable {
    public let fileManager: FileManager
    public let applicationName: String
    public let environment: [String: String]

    public init(
        fileManager: FileManager = .default,
        applicationName: String = "CodexBridge",
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.applicationName = applicationName
        self.environment = environment
    }

    public func baseRoot() throws -> URL {
        if let override = environment["CODEX_BRIDGE_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return applicationSupport.appendingPathComponent(applicationName, isDirectory: true)
    }

    public func runtimePaths() throws -> RuntimePaths {
        let root = try baseRoot()
        return RuntimePaths(
            root: root,
            codexHome: root.appendingPathComponent("codex-home", isDirectory: true),
            workspaceRoot: root.appendingPathComponent("runtime-workspaces", isDirectory: true),
            importsRoot: root.appendingPathComponent("imports", isDirectory: true),
            libraryRoot: root.appendingPathComponent("library", isDirectory: true),
            styleMemoryRoot: root.appendingPathComponent("style-memory", isDirectory: true),
            logsRoot: root.appendingPathComponent("logs", isDirectory: true),
            diagnosticsRoot: root.appendingPathComponent("diagnostics", isDirectory: true)
        )
    }

    @discardableResult
    public func ensureBaseDirectories() throws -> RuntimePaths {
        let paths = try runtimePaths()
        for url in [paths.root, paths.codexHome, paths.workspaceRoot, paths.importsRoot, paths.libraryRoot, paths.styleMemoryRoot, paths.logsRoot, paths.diagnosticsRoot] {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return paths
    }

    public func workspaceURL(sessionID: String, createIfNeeded: Bool = true) throws -> URL {
        let workspace = try ensureBaseDirectories().workspaceRoot.appendingPathComponent(sessionID, isDirectory: true)
        if createIfNeeded {
            try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        }
        return workspace
    }

    public func resolveRelativePath(_ relativePath: String, within root: URL, createParents: Bool = true) throws -> URL {
        guard !relativePath.isEmpty else {
            throw RuntimePathResolverError.invalidRelativePath(relativePath)
        }
        guard !relativePath.hasPrefix("/") else {
            throw RuntimePathResolverError.absolutePathRejected(relativePath)
        }

        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if components.contains("..") {
            throw RuntimePathResolverError.pathTraversalRejected(relativePath)
        }

        let resolved = components.reduce(root) { partial, component in
            partial.appendingPathComponent(component, isDirectory: false)
        }.standardizedFileURL

        let standardizedRoot = root.standardizedFileURL.path
        let standardizedResolved = resolved.path
        guard standardizedResolved == standardizedRoot || standardizedResolved.hasPrefix(standardizedRoot + "/") else {
            throw RuntimePathResolverError.pathEscapedRoot(relativePath)
        }

        if createParents {
            try fileManager.createDirectory(at: resolved.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        return resolved
    }

    public func resolveWorkspacePath(_ relativePath: String, in workspaceRoot: URL, createParents: Bool = true) throws -> URL {
        try resolveRelativePath(relativePath, within: workspaceRoot, createParents: createParents)
    }

    public func genericEnvironment() throws -> [String: String] {
        let paths = try ensureBaseDirectories()
        return [
            "CODEX_HOME": paths.codexHome.path,
            "CODEX_BRIDGE_WORKSPACE_ROOT": paths.workspaceRoot.path,
            "CODEX_BRIDGE_IMPORTS_ROOT": paths.importsRoot.path,
            "CODEX_BRIDGE_LIBRARY_ROOT": paths.libraryRoot.path,
            "CODEX_BRIDGE_STYLE_MEMORY_ROOT": paths.styleMemoryRoot.path,
            "CODEX_BRIDGE_LOGS_ROOT": paths.logsRoot.path,
            "CODEX_BRIDGE_DIAGNOSTICS_ROOT": paths.diagnosticsRoot.path,
            "CODEX_BRIDGE_MAS_MODE": "1",
        ]
    }
}
