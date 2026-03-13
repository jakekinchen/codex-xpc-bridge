import Foundation
import CodexBridgeContract

public protocol ToolHandling: Sendable {
    func execute(toolCall: ToolCallPayload, sessionID: String) async throws -> ToolResultPayload
}

public typealias ToolHandlingFactory = @Sendable (RuntimePaths, RuntimePathResolver) -> any ToolHandling

public enum ToolExecutionError: LocalizedError, Equatable {
    case unsupportedTool(ToolID)
    case missingArgument(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedTool(let tool):
            return "Tool is not in the MAS allowlist: \(tool.rawValue)"
        case .missingArgument(let key):
            return "Missing required argument: \(key)"
        }
    }
}

public actor DemoToolExecutor: ToolHandling {
    public let paths: RuntimePaths
    private let resolver: RuntimePathResolver
    private let fileManager: FileManager

    public init(paths: RuntimePaths, resolver: RuntimePathResolver = RuntimePathResolver(), fileManager: FileManager = .default) {
        self.paths = paths
        self.resolver = resolver
        self.fileManager = fileManager
    }

    public func execute(_ invocation: ToolCallPayload) throws -> ToolResultPayload {
        try executeInternal(invocation, sessionID: nil)
    }

    public func execute(toolCall: ToolCallPayload, sessionID: String) async throws -> ToolResultPayload {
        try executeInternal(toolCall, sessionID: sessionID)
    }

    private func executeInternal(_ invocation: ToolCallPayload, sessionID: String?) throws -> ToolResultPayload {
        let toolID = invocation.toolName

        if toolID == DemoToolID.writeWorkspaceFile {
            return try writeWorkspaceFile(invocation, sessionID: sessionID)
        }
        if toolID == DemoToolID.readWorkspaceFile {
            return try readWorkspaceFile(invocation, sessionID: sessionID)
        }
        if toolID == DemoToolID.convertShader {
            return try convertShader(invocation, sessionID: sessionID)
        }
        if toolID == DemoToolID.validateShader {
            return try validateShader(invocation, sessionID: sessionID)
        }
        if toolID == DemoToolID.capturePreview {
            return try capturePreview(invocation, sessionID: sessionID)
        }
        if toolID == DemoToolID.saveStyleProfile {
            return try saveStyleProfile(invocation)
        }
        if toolID == DemoToolID.saveToLibrary {
            return try saveToLibrary(invocation, sessionID: sessionID)
        }
        if toolID == DemoToolID.importShader {
            return try importShader(invocation, sessionID: sessionID)
        }

        throw ToolExecutionError.unsupportedTool(toolID)
    }

    private func workspaceRoot(for sessionID: String?) throws -> URL {
        if let sessionID, !sessionID.isEmpty {
            return try resolver.workspaceURL(sessionID: sessionID)
        }
        return paths.workspaceRoot
    }

    private func writeWorkspaceFile(_ invocation: ToolCallPayload, sessionID: String?) throws -> ToolResultPayload {
        let relativePath = try stringArgument("path", in: invocation.arguments)
        let content = try stringArgument("content", in: invocation.arguments)
        let url = try resolver.resolveWorkspacePath(relativePath, in: workspaceRoot(for: sessionID))
        try Data(content.utf8).write(to: url)
        return ToolResultPayload(toolInvocationId: invocation.toolInvocationId, toolName: invocation.toolName, success: true, summary: "Workspace file written.", outputs: ["path": .string(relativePath)], artifactPaths: [url.path])
    }

    private func readWorkspaceFile(_ invocation: ToolCallPayload, sessionID: String?) throws -> ToolResultPayload {
        let relativePath = try stringArgument("path", in: invocation.arguments)
        let url = try resolver.resolveWorkspacePath(relativePath, in: workspaceRoot(for: sessionID), createParents: false)
        let content = try String(contentsOf: url)
        return ToolResultPayload(toolInvocationId: invocation.toolInvocationId, toolName: invocation.toolName, success: true, summary: "Workspace file read.", outputs: ["path": .string(relativePath), "content": .string(content)])
    }

    private func convertShader(_ invocation: ToolCallPayload, sessionID: String?) throws -> ToolResultPayload {
        let sourcePath = try stringArgument("sourcePath", in: invocation.arguments)
        let targetPath = invocation.arguments["targetPath"]?.stringValue ?? sourcePath.replacingOccurrences(of: ".glsl", with: ".wgsl")
        let root = try workspaceRoot(for: sessionID)
        let sourceURL = try resolver.resolveWorkspacePath(sourcePath, in: root, createParents: false)
        let targetURL = try resolver.resolveWorkspacePath(targetPath, in: root)
        let source = try String(contentsOf: sourceURL)
        let converted = "// Converted by CodexBridge\n" + source.replacingOccurrences(of: "gl_FragColor", with: "outputColor")
        try Data(converted.utf8).write(to: targetURL)
        return ToolResultPayload(toolInvocationId: invocation.toolInvocationId, toolName: invocation.toolName, success: true, summary: "Shader converted to WGSL.", outputs: ["sourcePath": .string(sourcePath), "targetPath": .string(targetPath)], artifactPaths: [targetURL.path])
    }

    private func validateShader(_ invocation: ToolCallPayload, sessionID: String?) throws -> ToolResultPayload {
        let sourcePath = try stringArgument("sourcePath", in: invocation.arguments)
        let sourceURL = try resolver.resolveWorkspacePath(sourcePath, in: workspaceRoot(for: sessionID), createParents: false)
        let source = try String(contentsOf: sourceURL)
        let valid = source.contains("fn") || source.contains("outputColor")
        let reportURL = paths.diagnosticsRoot.appendingPathComponent("validation-\(invocation.toolInvocationId).json")
        let report = ["sourcePath": sourcePath, "valid": valid ? "true" : "false"]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try Data(data).write(to: reportURL)
        return ToolResultPayload(toolInvocationId: invocation.toolInvocationId, toolName: invocation.toolName, success: valid, summary: valid ? "Shader validation passed." : "Shader validation reported issues.", artifactPaths: [reportURL.path])
    }

    private func capturePreview(_ invocation: ToolCallPayload, sessionID: String?) throws -> ToolResultPayload {
        let name = invocation.arguments["name"]?.stringValue ?? invocation.toolInvocationId
        let targetURL = try resolver.resolveWorkspacePath("previews/\(name).ppm", in: workspaceRoot(for: sessionID))
        let ppm = "P3\n2 2\n255\n245 190 80   30 60 140\n30 60 140   245 190 80\n"
        try Data(ppm.utf8).write(to: targetURL)
        return ToolResultPayload(toolInvocationId: invocation.toolInvocationId, toolName: invocation.toolName, success: true, summary: "Preview captured.", artifactPaths: [targetURL.path])
    }

    private func saveStyleProfile(_ invocation: ToolCallPayload) throws -> ToolResultPayload {
        let name = invocation.arguments["name"]?.stringValue ?? "default-style"
        let profile = invocation.arguments["profile"]?.foundationObject ?? [:]
        let targetURL = paths.styleMemoryRoot.appendingPathComponent("\(name).json")
        let data = try JSONSerialization.data(withJSONObject: profile, options: [.prettyPrinted, .sortedKeys])
        try Data(data).write(to: targetURL)
        return ToolResultPayload(toolInvocationId: invocation.toolInvocationId, toolName: invocation.toolName, success: true, summary: "Style profile saved.", artifactPaths: [targetURL.path])
    }

    private func saveToLibrary(_ invocation: ToolCallPayload, sessionID: String?) throws -> ToolResultPayload {
        let sourcePath = try stringArgument("sourcePath", in: invocation.arguments)
        let sourceURL = try resolver.resolveWorkspacePath(sourcePath, in: workspaceRoot(for: sessionID), createParents: false)
        let name = invocation.arguments["name"]?.stringValue ?? sourceURL.lastPathComponent
        let targetURL = paths.libraryRoot.appendingPathComponent(name)
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        try fileManager.copyItem(at: sourceURL, to: targetURL)
        return ToolResultPayload(toolInvocationId: invocation.toolInvocationId, toolName: invocation.toolName, success: true, summary: "Artifact saved to library.", artifactPaths: [targetURL.path])
    }

    private func importShader(_ invocation: ToolCallPayload, sessionID: String?) throws -> ToolResultPayload {
        let externalPath = try stringArgument("sourcePath", in: invocation.arguments)
        let sourceURL = URL(fileURLWithPath: externalPath)
        let destination = invocation.arguments["destinationPath"]?.stringValue ?? "imports/\(sourceURL.lastPathComponent)"
        let targetURL = try resolver.resolveWorkspacePath(destination, in: workspaceRoot(for: sessionID))
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        try fileManager.copyItem(at: sourceURL, to: targetURL)
        return ToolResultPayload(toolInvocationId: invocation.toolInvocationId, toolName: invocation.toolName, success: true, summary: "Shader imported.", artifactPaths: [targetURL.path])
    }

    private func stringArgument(_ key: String, in arguments: [String: JSONValue]) throws -> String {
        guard let value = arguments[key]?.stringValue else {
            throw ToolExecutionError.missingArgument(key)
        }
        return value
    }
}
