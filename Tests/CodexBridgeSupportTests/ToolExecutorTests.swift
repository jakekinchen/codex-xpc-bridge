import XCTest
@testable import CodexBridgeContract
@testable import CodexBridgeSupport

final class ToolExecutorTests: XCTestCase {
    func testBoundedToolExecutorRunsCompleteArtifactPipeline() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resolver = RuntimePathResolver(environment: ["CODEX_BRIDGE_ROOT": root.path])
        let paths = try resolver.ensureBaseDirectories()
        let executor = DemoToolExecutor(paths: paths, resolver: resolver)
        let sessionID = "tool-suite"

        let importedSource = root.appendingPathComponent("external-input.glsl")
        try Data("void main() { gl_FragColor = vec4(1.0); }".utf8).write(to: importedSource)

        let importResult = try await executor.execute(toolCall: ToolCallPayload(
            toolInvocationId: "import-1",
            toolName: DemoToolID.importShader,
            summary: "Import shader",
            requiresApproval: false,
            arguments: ["sourcePath": .string(importedSource.path)]
        ), sessionID: sessionID)
        XCTAssertTrue(importResult.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: importResult.artifactPaths[0]))

        let writeResult = try await executor.execute(toolCall: ToolCallPayload(
            toolInvocationId: "write-1",
            toolName: DemoToolID.writeWorkspaceFile,
            summary: "Write draft",
            requiresApproval: false,
            arguments: ["path": .string("drafts/demo-input.glsl"), "content": .string("void main() { gl_FragColor = vec4(1.0); }")]
        ), sessionID: sessionID)
        XCTAssertTrue(writeResult.success)

        let convertResult = try await executor.execute(toolCall: ToolCallPayload(
            toolInvocationId: "convert-1",
            toolName: DemoToolID.convertShader,
            summary: "Convert shader",
            requiresApproval: true,
            arguments: ["sourcePath": .string("drafts/demo-input.glsl"), "targetPath": .string("drafts/demo-output.wgsl")]
        ), sessionID: sessionID)
        XCTAssertTrue(convertResult.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: convertResult.artifactPaths[0]))

        let readResult = try await executor.execute(toolCall: ToolCallPayload(
            toolInvocationId: "read-1",
            toolName: DemoToolID.readWorkspaceFile,
            summary: "Read WGSL",
            requiresApproval: false,
            arguments: ["path": .string("drafts/demo-output.wgsl")]
        ), sessionID: sessionID)
        XCTAssertTrue(readResult.success)
        XCTAssertTrue(readResult.outputs["content"]?.stringValue?.contains("outputColor") == true)

        let validateResult = try await executor.execute(toolCall: ToolCallPayload(
            toolInvocationId: "validate-1",
            toolName: DemoToolID.validateShader,
            summary: "Validate shader",
            requiresApproval: false,
            arguments: ["sourcePath": .string("drafts/demo-output.wgsl")]
        ), sessionID: sessionID)
        XCTAssertTrue(validateResult.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: validateResult.artifactPaths[0]))

        let previewResult = try await executor.execute(toolCall: ToolCallPayload(
            toolInvocationId: "preview-1",
            toolName: DemoToolID.capturePreview,
            summary: "Capture preview",
            requiresApproval: false,
            arguments: ["name": .string("demo-preview")]
        ), sessionID: sessionID)
        XCTAssertTrue(previewResult.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewResult.artifactPaths[0]))

        let styleResult = try await executor.execute(toolCall: ToolCallPayload(
            toolInvocationId: "style-1",
            toolName: DemoToolID.saveStyleProfile,
            summary: "Save style",
            requiresApproval: false,
            arguments: ["name": .string("sunrise"), "profile": .object(["accent": .string("amber")])]
        ), sessionID: sessionID)
        XCTAssertTrue(styleResult.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: styleResult.artifactPaths[0]))

        let libraryResult = try await executor.execute(toolCall: ToolCallPayload(
            toolInvocationId: "library-1",
            toolName: DemoToolID.saveToLibrary,
            summary: "Save to library",
            requiresApproval: true,
            arguments: ["sourcePath": .string("drafts/demo-output.wgsl"), "name": .string("demo-output.wgsl")]
        ), sessionID: sessionID)
        XCTAssertTrue(libraryResult.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryResult.artifactPaths[0]))
    }
}
