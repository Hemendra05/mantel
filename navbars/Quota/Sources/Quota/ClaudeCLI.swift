import Foundation

struct AuthStatus: Codable, Sendable, Equatable {
    var loggedIn: Bool = false
    var authMethod: String?
    var apiProvider: String?
    var email: String?
    var orgId: String?
    var orgName: String?
    var subscriptionType: String?
}

enum CLIError: LocalizedError, Equatable {
    case notFound
    case failed(status: Int32, message: String)
    case undecodable(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            "claude CLI not found"
        case let .failed(status, message):
            message.isEmpty ? "claude exited \(status)" : message
        case .undecodable:
            "unexpected output from claude"
        }
    }
}

/// Broker for `claude auth status --json`. Deliberately shells out to the CLI rather
/// than reading the OAuth token: the CLI owns credential access and refresh, so this
/// app never handles, stores, or can leak the token.
enum ClaudeCLI {
    /// A .app launched from Finder gets a minimal PATH, so `claude` must be resolved
    /// by absolute path rather than looked up on PATH.
    static func locate() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appending(path: ".local/bin/claude"),
            home.appending(path: ".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
            URL(fileURLWithPath: "/usr/bin/claude"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func authStatus() throws -> AuthStatus {
        guard let binary = locate() else { throw CLIError.notFound }

        let task = Process()
        task.executableURL = binary
        task.arguments = ["auth", "status", "--json"]
        // Inherit nothing that could redirect auth at a different account.
        task.environment = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("ANTHROPIC_")
        }

        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err
        try task.run()

        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw CLIError.failed(
                status: task.terminationStatus,
                message: String(decoding: errData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let status = try? JSONDecoder().decode(AuthStatus.self, from: data) else {
            throw CLIError.undecodable(String(decoding: data, as: UTF8.self))
        }
        return status
    }
}
