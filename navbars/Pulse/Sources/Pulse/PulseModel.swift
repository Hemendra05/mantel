import Foundation
import Observation

@MainActor
@Observable
final class PulseModel {
    var snapshot = Snapshot()
    var cpuHistory: [Double] = []
    var memHistory: [Double] = []
    var topByCPU: [ProcessRow] = []
    var topByMemory: [ProcessRow] = []
    var interval: TimeInterval = 1.0

    /// Panel visibility gates the `ps` fork; the mach counters are cheap enough
    /// to sample unconditionally.
    var panelVisible = false

    private let metrics = SystemMetrics()
    private var timer: Timer?
    private var sampleTask: Task<Void, Never>?
    private var primed = false

    var onUpdate: (() -> Void)?

    func start() {
        tick()
        restartTimer()
    }

    func setInterval(_ seconds: TimeInterval) {
        interval = seconds
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let snap = metrics.sample()
        // First delta-based CPU sample is meaningless; keep it out of the history.
        guard primed else { primed = true; snapshot = snap; return }

        snapshot = snap
        append(&cpuHistory, snap.cpu.busy)
        append(&memHistory, snap.memory.usedFraction)
        onUpdate?()

        if panelVisible { refreshProcesses() }
    }

    /// Cancels any in-flight sample so a fast close/reopen cannot let an older
    /// `ps` result land after a newer one.
    func refreshProcesses() {
        sampleTask?.cancel()
        sampleTask = Task { [weak self] in
            let top = await ProcessSampler.top()
            guard !Task.isCancelled else { return }
            self?.topByCPU = top.byCPU
            self?.topByMemory = top.byMemory
        }
    }

    private func append(_ history: inout [Double], _ value: Double) {
        history.append(value)
        if history.count > StatusItemRenderer.historyLength {
            history.removeFirst(history.count - StatusItemRenderer.historyLength)
        }
    }
}

// MARK: - Formatting

enum Fmt {
    static func bytes(_ value: UInt64) -> String {
        let gb = Double(value) / 1_073_741_824
        if gb >= 10 { return String(format: "%.0f GB", gb) }
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(value) / 1_048_576)
    }

    /// Single-character unit for legends, where "1.9 GB" would wrap.
    static func compact(_ value: UInt64) -> String {
        let gb = Double(value) / 1_073_741_824
        if gb >= 10 { return String(format: "%.0fG", gb) }
        if gb >= 1 { return String(format: "%.1fG", gb) }
        return String(format: "%.0fM", Double(value) / 1_048_576)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86400, hours = (total % 86400) / 3600, minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func pressure(_ level: Int32) -> String {
        switch level {
        case 1: "normal"
        case 2: "warning"
        case 4: "critical"
        default: "level \(level)"
        }
    }
}
