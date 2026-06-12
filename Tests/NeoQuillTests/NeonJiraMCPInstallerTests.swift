import XCTest
@testable import NeoQuill

final class NeonJiraMCPInstallerTests: XCTestCase {
    func testInstallArgumentsUseConfiguredPackageSource() {
        XCTAssertEqual(
            NeonJiraMCPInstaller.installArguments(package: " github:company/jira-mcp "),
            ["install", "-g", "github:company/jira-mcp"]
        )
    }

    func testMCPConfigSnippetUsesProvidedCommand() throws {
        let snippet = NeonJiraMCPInstaller.mcpConfigSnippet(command: "/opt/homebrew/bin/jira-mcp")

        XCTAssertTrue(snippet.contains("\"neon-jira\""))
        XCTAssertEqual(try command(from: snippet), "/opt/homebrew/bin/jira-mcp")
    }

    func testMCPConfigSnippetEscapesConfiguredCommand() throws {
        let snippet = NeonJiraMCPInstaller.mcpConfigSnippet(command: "/tmp/company \"jira\"")

        XCTAssertEqual(try command(from: snippet), "/tmp/company \"jira\"")
    }

    func testMCPConfigSnippetFallsBackToDefaultCommand() throws {
        let snippet = NeonJiraMCPInstaller.mcpConfigSnippet(command: " ")

        XCTAssertEqual(try command(from: snippet), "jira-mcp")
    }

    func testStatusDerivesInstallAndInstalledFlags() {
        let status = NeonJiraMCPStatus(
            nodePath: "/opt/homebrew/bin/node",
            npmPath: "/opt/homebrew/bin/npm",
            mcpPath: "/opt/homebrew/bin/jira-mcp",
            jiraPath: nil
        )

        XCTAssertTrue(status.canInstall)
        XCTAssertTrue(status.installed)
    }

    private func command(from snippet: String) throws -> String {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(snippet.utf8)) as? [String: Any])
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        let jira = try XCTUnwrap(servers["neon-jira"] as? [String: Any])
        return try XCTUnwrap(jira["command"] as? String)
    }
}
