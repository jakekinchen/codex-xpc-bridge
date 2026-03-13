import XCTest
@testable import CodexBridgeSupport

final class RuntimePathResolverTests: XCTestCase {
    func testResolvesWorkspaceFileInsideRoot() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resolver = RuntimePathResolver(environment: ["CODEX_BRIDGE_ROOT": tempRoot.path])
        let workspace = try resolver.workspaceURL(sessionID: "session-1")
        let url = try resolver.resolveWorkspacePath("Drafts/file.txt", in: workspace)
        XCTAssertTrue(url.path.hasPrefix(tempRoot.path))
        XCTAssertTrue(url.path.hasSuffix("Drafts/file.txt"))
    }

    func testRejectsTraversalAndAbsolutePaths() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resolver = RuntimePathResolver(environment: ["CODEX_BRIDGE_ROOT": tempRoot.path])
        let workspace = try resolver.workspaceURL(sessionID: "session-1")
        XCTAssertThrowsError(try resolver.resolveWorkspacePath("../escape.txt", in: workspace))
        XCTAssertThrowsError(try resolver.resolveWorkspacePath("/etc/passwd", in: workspace))
    }
}
