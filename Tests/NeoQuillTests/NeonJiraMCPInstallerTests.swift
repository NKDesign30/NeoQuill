import XCTest
@testable import NeoQuill

final class NeonJiraMCPInstallerTests: XCTestCase {
    func testInstallArgumentsUsePublicGitHubRepository() {
        XCTAssertEqual(
            NeonJiraMCPInstaller.installArguments,
            ["install", "-g", "github:NKDesign30/neon-jira-mcp"]
        )
    }

    func testMCPConfigSnippetUsesProvidedCommand() {
        let snippet = NeonJiraMCPInstaller.mcpConfigSnippet(command: "/opt/homebrew/bin/neon-jira-mcp")

        XCTAssertTrue(snippet.contains("\"neon-jira\""))
        XCTAssertTrue(snippet.contains("\"command\": \"/opt/homebrew/bin/neon-jira-mcp\""))
    }

    func testStatusDerivesInstallAndInstalledFlags() {
        let status = NeonJiraMCPStatus(
            nodePath: "/opt/homebrew/bin/node",
            npmPath: "/opt/homebrew/bin/npm",
            mcpPath: "/opt/homebrew/bin/neon-jira-mcp",
            jiraPath: nil
        )

        XCTAssertTrue(status.canInstall)
        XCTAssertTrue(status.installed)
    }
}
