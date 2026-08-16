import Darwin
import Foundation

struct MemoryBreakdown: Sendable {
    var total: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var free: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressureLevel: Int32 = 1
    var pageIns: UInt64 = 0
    var pageOuts: UInt64 = 0

    /// Matches Activity Monitor's "Memory Used", which is total minus cached files
    /// minus free — not app+wired+compressed. Those three leave ~0.8 GB of kernel
    /// and other internal pages unaccounted for, which AM never itemises.
    var used: UInt64 { UInt64(max(0, Int64(total) - Int64(cached) - Int64(free))) }

    /// The remainder AM hides, surfaced so the breakdown sums to `used`.
    var other: UInt64 {
        UInt64(max(0, Int64(used) - Int64(app) - Int64(wired) - Int64(compressed)))
    }

    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct CPUBreakdown: Sendable {
    var user: Double = 0
    var system: Double = 0
    var nice: Double = 0
    var perCore: [Double] = []

    var busy: Double { min(1, user + system + nice) }
}

struct Snapshot: Sendable {
    var cpu = CPUBreakdown()
    var memory = MemoryBreakdown()
    var loadAverage: (Double, Double, Double) = (0, 0, 0)
    var uptime: TimeInterval = 0
    var coreCount: Int = 0
    var perfCores: Int = 0
    var effCores: Int = 0
}

/// Samples kernel counters directly. CPU is delta-based, so the first sample
/// after init reports zero busy — callers should discard it.
final class SystemMetrics {
    private var previousTicks: [UInt32] = []
    // vm_statistics64 counts kernel pages; hw.pagesize matches it and avoids the
    // non-Sendable global `vm_kernel_page_size`.
    private let pageSize = UInt64(SystemMetrics.sysctlInt("hw.pagesize") ?? 16384)
    private let physicalMemory = ProcessInfo.processInfo.physicalMemory

    let coreCount = Int(ProcessInfo.processInfo.processorCount)
    lazy var perfCores = SystemMetrics.sysctlInt("hw.perflevel0.logicalcpu") ?? 0
    lazy var effCores = SystemMetrics.sysctlInt("hw.perflevel1.logicalcpu") ?? 0

    func sample() -> Snapshot {
        var snap = Snapshot()
        snap.cpu = sampleCPU()
        snap.memory = sampleMemory()
        snap.coreCount = coreCount
        snap.perfCores = perfCores
        snap.effCores = effCores

        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 {
            snap.loadAverage = (loads[0], loads[1], loads[2])
        }
        snap.uptime = SystemMetrics.uptime()
        return snap
    }

    // MARK: - CPU

    private func sampleCPU() -> CPUBreakdown {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                     &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS, let info else { return CPUBreakdown() }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        let cores = Int(cpuCount)
        var ticks = [UInt32](repeating: 0, count: cores * states)
        for i in 0..<(cores * states) { ticks[i] = UInt32(bitPattern: info[i]) }

        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count else { return CPUBreakdown() }

        var out = CPUBreakdown()
        var totals = (user: 0.0, system: 0.0, nice: 0.0, all: 0.0)
        out.perCore.reserveCapacity(cores)

        for core in 0..<cores {
            let base = core * states
            func delta(_ state: Int32) -> Double {
                let i = base + Int(state)
                // Kernel tick counters are 32-bit and wrap; treat wrap as no delta.
                return Double(ticks[i] &- previousTicks[i])
            }
            let user = delta(CPU_STATE_USER)
            let system = delta(CPU_STATE_SYSTEM)
            let nice = delta(CPU_STATE_NICE)
            let idle = delta(CPU_STATE_IDLE)
            let sum = user + system + nice + idle

            out.perCore.append(sum > 0 ? (user + system + nice) / sum : 0)
            totals.user += user
            totals.system += system
            totals.nice += nice
            totals.all += sum
        }

        if totals.all > 0 {
            out.user = totals.user / totals.all
            out.system = totals.system / totals.all
            out.nice = totals.nice / totals.all
        }
        return out
    }

    // MARK: - Memory

    private func sampleMemory() -> MemoryBreakdown {
        var mem = MemoryBreakdown()
        mem.total = physicalMemory

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return mem }

        func bytes(_ pages: some BinaryInteger) -> UInt64 { UInt64(pages) * pageSize }

        let purgeable = bytes(stats.purgeable_count)
        mem.wired = bytes(stats.wire_count)
        mem.compressed = bytes(stats.compressor_page_count)
        mem.app = bytes(stats.internal_page_count) - min(purgeable, bytes(stats.internal_page_count))
        mem.cached = bytes(stats.external_page_count) + purgeable
        mem.free = bytes(stats.free_count)
        mem.pageIns = UInt64(stats.pageins)
        mem.pageOuts = UInt64(stats.pageouts)

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            mem.swapUsed = swap.xsu_used
            mem.swapTotal = swap.xsu_total
        }
        mem.pressureLevel = Int32(SystemMetrics.sysctlInt("kern.memorystatus_vm_pressure_level") ?? 1)
        return mem
    }

    // MARK: - sysctl helpers

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            var small: Int32 = 0
            var s32 = MemoryLayout<Int32>.size
            guard sysctlbyname(name, &small, &s32, nil, 0) == 0 else { return nil }
            return Int(small)
        }
        return value
    }

    static func uptime() -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec != 0
        else { return 0 }
        return Date().timeIntervalSince1970 - Double(boot.tv_sec)
    }
}
