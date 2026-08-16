import Foundation

struct ProcessRow: Sendable, Identifiable {
    var id: Int32 { pid }
    let pid: Int32
    let cpu: Double      // percent, summed across cores (may exceed 100)
    let memPercent: Double
    let rss: UInt64      // bytes
    let name: String
}

enum ProcessSampler {
    /// Runs `ps` off the main actor. Only called while the panel is visible.
    static func top(limit: Int = 5) async -> (byCPU: [ProcessRow], byMemory: [ProcessRow]) {
        let rows = await Task.detached(priority: .userInitiated) { parse(run()) }.value
        return (Array(rows.sorted { $0.cpu > $1.cpu }.prefix(limit)),
                Array(rows.sorted { $0.rss > $1.rss }.prefix(limit)))
    }

    private static func run() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Aco", "pid=,pcpu=,pmem=,rss=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private static func parse(_ output: String) -> [ProcessRow] {
        output.split(separator: "\n").compactMap { line in
            // comm can contain spaces, so split off the four numeric columns only.
            let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count == 5,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let memPct = Double(parts[2]),
                  let rssKB = UInt64(parts[3])
            else { return nil }
            return ProcessRow(pid: pid, cpu: cpu, memPercent: memPct,
                              rss: rssKB * 1024,
                              name: parts[4].trimmingCharacters(in: .whitespaces))
        }
    }
}
