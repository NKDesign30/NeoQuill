import Foundation

struct NeonJiraMCPStatus: Equatable, Sendable {
    let nodePath: String?
    let npmPath: String?
    let mcpPath: String?
    let jiraPath: String?

    static let empty = NeonJiraMCPStatus(
        nodePath: nil,
        npmPath: nil,
        mcpPath: nil,
        jiraPath: nil
    )

    var installed: Bool {
        mcpPath != nil
    }

    var canInstall: Bool {
        npmPath != nil
    }
}

enum NeonJiraMCPInstallerError: LocalizedError, Equatable {
    case npmMissing
    case commandFailed(command: String, status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .npmMissing:
            return "npm wurde nicht gefunden."
        case .commandFailed(let command, let status, let output):
            return "\(command) fehlgeschlagen (\(status)): \(output)"
        }
    }
}

enum NeonJiraMCPInstaller {
    static let repository = "github:NKDesign30/neon-jira-mcp"
    static let installArguments = ["install", "-g", repository]

    static func currentStatus() async -> NeonJiraMCPStatus {
        await Task.detached(priority: .utility) {
            NeonJiraMCPStatus(
                nodePath: executablePath("node"),
                npmPath: executablePath("npm"),
                mcpPath: executablePath("neon-jira-mcp"),
                jiraPath: executablePath("jira")
            )
        }.value
    }

    static func install() async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let npmPath = executablePath("npm") else {
                throw NeonJiraMCPInstallerError.npmMissing
            }
            return try run(executable: npmPath, arguments: installArguments)
        }.value
    }

    static func mcpConfigSnippet(command: String) -> String {
        """
        {
          "mcpServers": {
            "neon-jira": {
              "command": "\(command)"
            }
          }
        }
        """
    }

    private static func executablePath(_ name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)",
        ]
        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return match
        }

        let resolved = try? run(executable: "/usr/bin/env", arguments: ["which", name])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return resolved?.isEmpty == false ? resolved : nil
    }

    private static func run(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let output = [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard process.terminationStatus == 0 else {
            let command = ([executable] + arguments).joined(separator: " ")
            throw NeonJiraMCPInstallerError.commandFailed(
                command: command,
                status: process.terminationStatus,
                output: output
            )
        }

        return output
    }
}
