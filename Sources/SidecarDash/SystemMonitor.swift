import Darwin
import Foundation

/// Live CPU, memory and disk figures for this Mac. CPU and memory are sampled
/// every 2 seconds, disk every minute. Nothing leaves the machine.
@MainActor
final class SystemMonitor: ObservableObject {
    struct Snapshot: Equatable {
        var cpuPercent: Double = 0
        var cpuHistory: [Double] = []
        var cores = ProcessInfo.processInfo.activeProcessorCount
        var load1: Double = 0
        var memUsed: Double = 0      // bytes, the way Activity Monitor counts "Memory Used"
        var memTotal = Double(ProcessInfo.processInfo.physicalMemory)
        var memCompressed: Double = 0
        var swapUsed: Double = 0
        var diskUsed: Double = 0
        var diskTotal: Double = 0
        var bootDate: Date?

        var memPercent: Double { memTotal > 0 ? memUsed / memTotal * 100 : 0 }
        var diskPercent: Double { diskTotal > 0 ? diskUsed / diskTotal * 100 : 0 }
        var diskFree: Double { max(diskTotal - diskUsed, 0) }
    }

    @Published private(set) var snapshot = Snapshot()

    static let historyLength = 60
    private var lastTicks: [UInt32]?
    private var timers: [Timer] = []

    func start() {
        snapshot.bootDate = Self.bootDate()
        sampleFast()
        sampleDisk()
        add(every: 2) { [weak self] in self?.sampleFast() }
        add(every: 60) { [weak self] in self?.sampleDisk() }
    }

    func loadDemo() {
        var s = Snapshot()
        s.cores = 12
        s.cpuHistory = (0..<Self.historyLength).map { i in
            let t = Double(i)
            return 18 + 10 * sin(t / 6) + 7 * sin(t / 2.3) + (i > 48 ? 14 : 0)
        }
        s.cpuPercent = s.cpuHistory.last ?? 0
        s.load1 = 3.42
        s.memTotal = 32 * 1_073_741_824
        s.memUsed = 21.6 * 1_073_741_824
        s.memCompressed = 2.1 * 1_073_741_824
        s.diskTotal = 994.66e9
        s.diskUsed = 612.4e9
        s.bootDate = Date().addingTimeInterval(-(3 * 86_400 + 5 * 3600))
        snapshot = s
    }

    private func add(every seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: seconds, repeats: true) { _ in
            Task { @MainActor in action() }
        }
        timer.tolerance = seconds * 0.2
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    private func sampleFast() {
        var s = snapshot
        if let cpu = cpuPercent() {
            s.cpuPercent = cpu
            s.cpuHistory.append(cpu)
            if s.cpuHistory.count > Self.historyLength { s.cpuHistory.removeFirst(s.cpuHistory.count - Self.historyLength) }
        }
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) > 0 { s.load1 = loads[0] }
        if let mem = Self.memory() {
            s.memUsed = mem.used
            s.memCompressed = mem.compressed
        }
        s.swapUsed = Self.swapUsed()
        snapshot = s
    }

    private func sampleDisk() {
        let root = URL(fileURLWithPath: "/")
        guard let values = try? root.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                              .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return }
        // Same "available" figure Finder shows (purgeable space counts as free).
        snapshot.diskTotal = Double(total)
        snapshot.diskUsed = Double(total) - Double(free)
    }

    /// Busy share of all cores since the previous sample.
    private func cpuPercent() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3] // user, system, idle, nice
        defer { lastTicks = ticks }
        guard let last = lastTicks else { return nil }
        let d = zip(ticks, last).map { Double($0 &- $1) }
        let total = d.reduce(0, +)
        guard total > 0 else { return nil }
        return (d[0] + d[1] + d[3]) / total * 100
    }

    private static func memory() -> (used: Double, compressed: Double)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let page = Double(vm_kernel_page_size)
        // App memory + wired + compressed, as in Activity Monitor.
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let wired = Double(stats.wire_count)
        let compressed = Double(stats.compressor_page_count)
        return ((app + wired + compressed) * page, compressed * page)
    }

    private static func swapUsed() -> Double {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Double(usage.xsu_used)
    }

    private static func bootDate() -> Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec))
    }
}

func bytesLabel(_ bytes: Double) -> String {
    let gb = bytes / 1_073_741_824
    if gb >= 1000 { return String(format: "%.1f TB", gb / 1024) }
    return gb >= 100 ? String(format: "%.0f GB", gb) : String(format: "%.1f GB", gb)
}

/// Disk sizes in decimal units, matching Finder and About This Mac.
func diskLabel(_ bytes: Double) -> String {
    let gb = bytes / 1e9
    if gb >= 1000 { return String(format: "%.2f TB", gb / 1000) }
    return String(format: "%.0f GB", gb)
}
