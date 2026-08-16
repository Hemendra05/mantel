import Foundation
import Observation

@MainActor
@Observable
final class QuotaModel {
    var status = AuthStatus()
    var error: String?
    var lastUpdated: Date?
    var refreshing = false

    /// Spawns a CLI process, so this polls on the order of minutes, not seconds.
    var interval: TimeInterval = 300

    private var timer: Timer?

    var onUpdate: (() -> Void)?

    var planLabel: String {
        guard let plan = status.subscriptionType, !plan.isEmpty else { return "—" }
        return plan.count <= 3 ? plan.uppercased() : plan.capitalized
    }

    var accountLabel: String { status.email ?? "not signed in" }

    var orgLabel: String {
        guard let org = status.orgName, !org.isEmpty else { return "—" }
        // The default personal org is named "<email>'s Organization", which is noise.
        if let email = status.email, org.hasPrefix(email) { return "Personal" }
        return org
    }

    func start() {
        refresh()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try ClaudeCLI.authStatus() }
            }.value
            guard let self else { return }
            switch result {
            case let .success(status):
                self.status = status
                self.error = status.loggedIn ? nil : "signed out"
            case let .failure(failure):
                self.error = (failure as? CLIError)?.errorDescription
                    ?? failure.localizedDescription
                self.status = AuthStatus()
            }
            self.lastUpdated = Date()
            self.refreshing = false
            self.onUpdate?()
        }
    }
}

enum QuotaFmt {
    static func relative(_ date: Date?) -> String {
        guard let date else { return "never" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 10 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
