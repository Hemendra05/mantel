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

struct UsageLimit: Sendable, Equatable, Identifiable {
    let label: String       // "session", "week (all models)"
    let percent: Int
    let resets: String?     // "Aug 17 at 5:10am (Asia/Calcutta)"
    var id: String { label }
    var fraction: Double { Double(percent) / 100 }
}

struct UsageSnapshot: Sendable, Equatable {
    var limits: [UsageLimit] = []
    var note: String?

    var session: UsageLimit? { limits.first { $0.label.contains("session") } }
    var week: UsageLimit? { limits.first { $0.label.contains("week") } }
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
        let data = try run(["auth", "status", "--json"], timeout: 20)
        guard let status = try? JSONDecoder().decode(AuthStatus.self, from: data) else {
            throw CLIError.undecodable(String(decoding: data, as: UTF8.self))
        }
        return status
    }

    /// `/usage` is a local command: it reports zero turns and zero cost, so polling it
    /// does not consume the quota it reports. `--no-session-persistence` keeps each
    /// poll from leaving a transcript behind in ~/.claude/projects.
    static func usage() throws -> UsageSnapshot {
        let data = try run(["-p", "/usage",
                            "--max-turns", "1",
                            "--output-format", "json",
                            "--no-session-persistence"], timeout: 45)
        struct Envelope: Decodable { let result: String? }
        guard let text = (try? JSONDecoder().decode(Envelope.self, from: data))?.result else {
            throw CLIError.undecodable(String(decoding: data, as: UTF8.self))
        }
        return parseUsage(text)
    }

    /// Parsed positionally rather than by regex: the text is human-facing and its
    /// wording varies by plan, so anything unrecognised is skipped, not guessed at.
    static func parseUsage(_ text: String) -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if snapshot.note == nil, line.hasPrefix("You are currently") {
                snapshot.note = line
            }
            guard line.hasPrefix("Current "),
                  let colon = line.firstIndex(of: ":") else { continue }

            let label = line[line.index(line.startIndex, offsetBy: 8)..<colon]
                .trimmingCharacters(in: .whitespaces)
            var rest = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)

            guard let pctEnd = rest.firstIndex(of: "%"),
                  let percent = Int(rest[rest.startIndex..<pctEnd]
                      .trimmingCharacters(in: .whitespaces)) else { continue }

            var resets: String?
            if let marker = rest.range(of: "resets ") {
                resets = String(rest[marker.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            rest = ""
            snapshot.limits.append(
                UsageLimit(label: label, percent: percent, resets: resets))
        }
        return snapshot
    }

    private static func run(_ arguments: [String], timeout: TimeInterval) throws -> Data {
        guard let binary = locate() else { throw CLIError.notFound }

        let task = Process()
        task.executableURL = binary
        task.arguments = arguments
        // Strip ANTHROPIC_* so a stray key cannot redirect this at another account.
        task.environment = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("ANTHROPIC_")
        }

        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err
        try task.run()

        // Watchdog: a wedged CLI must not hang the menu bar app forever.
        let deadline = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)

        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        deadline.cancel()

        guard task.terminationStatus == 0 else {
            throw CLIError.failed(
                status: task.terminationStatus,
                message: String(decoding: errData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }
}
