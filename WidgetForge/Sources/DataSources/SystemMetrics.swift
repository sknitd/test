import Foundation

/// A fixed-capacity history buffer for sparklines and charts.
struct RingBuffer: Sendable {
    private(set) var values: [Double] = []
    let capacity: Int
    init(capacity: Int) { self.capacity = max(1, capacity) }

    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    var json: JSONValue { .array(values.map { .number($0) }) }
}

/// Fixed metrics used by tests and SwiftUI previews. Values are whatever the caller supplies.
final class StaticMetricsProvider: SystemMetricsProvider {
    var values: [String: JSONValue]
    init(_ values: [String: JSONValue] = [:]) { self.values = values }
    func snapshot(metric: String) -> JSONValue? { values[metric] }
}

#if canImport(Darwin)
import Darwin
import IOKit
import IOKit.ps

/// Reads real system metrics through documented Mach, BSD and IOKit interfaces.
///
/// Rates (CPU utilisation, network and disk throughput) are differences between two samples, so call
/// `sample()` on a steady cadence. Nothing here needs special entitlements and all of it works in the sandbox.
final class SystemMetricsCollector: SystemMetricsProvider {
    static let knownMetrics = ["cpu", "memory", "storage", "network", "battery", "system"]

    private let lock = NSLock()
    private var previousTicks: [[UInt32]] = []
    private var previousNetwork: (rx: UInt64, tx: UInt64, time: Double)?
    private var previousDisk: (read: UInt64, write: UInt64, time: Double)?
    private var networkTotals: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var accumulatedRx: UInt64 = 0
    private var accumulatedTx: UInt64 = 0

    private var cpuHistory = RingBuffer(capacity: 60)
    private var memoryHistory = RingBuffer(capacity: 60)
    private var downHistory = RingBuffer(capacity: 60)
    private var upHistory = RingBuffer(capacity: 60)
    private var batteryHistory = RingBuffer(capacity: 120)
    private var lastBatterySample = 0.0

    private var latest: [String: JSONValue] = [:]
    private(set) var sampleCount = 0

    init() {}

    func snapshot(metric: String) -> JSONValue? {
        lock.lock(); defer { lock.unlock() }
        return latest[metric]
    }

    /// Take one reading of everything. Cheap (well under a millisecond of CPU on current hardware; the real
    /// figure is reported by the app's diagnostics, not assumed here).
    @discardableResult
    func sample() -> [String: JSONValue] {
        lock.lock(); defer { lock.unlock() }
        let time = ProcessInfo.processInfo.systemUptime
        latest["cpu"] = readCPU()
        latest["memory"] = readMemory()
        latest["storage"] = readStorage(time: time)
        latest["network"] = readNetwork(time: time)
        latest["battery"] = readBattery(time: time)
        latest["system"] = readSystem()
        sampleCount += 1
        return latest
    }

    // MARK: CPU

    private func readCPU() -> JSONValue {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS, let info else {
            return ["available": false]
        }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var ticks: [[UInt32]] = []
        for cpu in 0..<Int(cpuCount) {
            let base = Int(CPU_STATE_MAX) * cpu
            ticks.append((0..<Int(CPU_STATE_MAX)).map { UInt32(bitPattern: info[base + $0]) })
        }
        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count else {
            // First sample: no interval to measure yet.
            return ["available": true, "usage": .null, "cores": [], "coreCount": .number(Double(ticks.count)), "history": cpuHistory.json]
        }
        var perCore: [Double] = []
        var busyTotal = 0.0, allTotal = 0.0, userTotal = 0.0, systemTotal = 0.0
        for (now, before) in zip(ticks, previousTicks) {
            let delta = zip(now, before).map { Double($0 &- $1) }
            let user = delta[Int(CPU_STATE_USER)] + delta[Int(CPU_STATE_NICE)]
            let system = delta[Int(CPU_STATE_SYSTEM)]
            let all = user + system + delta[Int(CPU_STATE_IDLE)]
            perCore.append(all > 0 ? (user + system) / all : 0)
            busyTotal += user + system; allTotal += all; userTotal += user; systemTotal += system
        }
        let usage = allTotal > 0 ? busyTotal / allTotal : 0
        cpuHistory.append(usage)
        return [
            "available": true,
            "usage": .number(usage),
            "user": .number(allTotal > 0 ? userTotal / allTotal : 0),
            "system": .number(allTotal > 0 ? systemTotal / allTotal : 0),
            "cores": .array(perCore.map { .number($0) }),
            "coreCount": .number(Double(perCore.count)),
            "history": cpuHistory.json,
        ]
    }

    // MARK: Memory

    private func readMemory() -> JSONValue {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return ["available": false] }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = Double(pageSize)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        // Same accounting as Activity Monitor's "Memory Used": app memory + wired + compressed.
        let app = (Double(stats.internal_page_count) - Double(stats.purgeable_count)) * page
        let wired = Double(stats.wire_count) * page
        let compressed = Double(stats.compressor_page_count) * page
        let used = min(total, max(0, app + wired + compressed))
        let usage = total > 0 ? used / total : 0
        memoryHistory.append(usage)

        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let hasLevel = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0
        let pressure: String
        switch level {
        case 2: pressure = "warning"
        case 4: pressure = "critical"
        default: pressure = hasLevel ? "normal" : "unknown"
        }
        return [
            "available": true,
            "usage": .number(usage),
            "usedBytes": .number(used),
            "availableBytes": .number(max(0, total - used)),
            "totalBytes": .number(total),
            "appBytes": .number(max(0, app)),
            "wiredBytes": .number(wired),
            "compressedBytes": .number(compressed),
            "cachedBytes": .number(Double(stats.external_page_count + stats.purgeable_count) * page),
            "pressure": .string(pressure),
            "history": memoryHistory.json,
        ]
    }

    // MARK: Storage

    private func readStorage(time: Double) -> JSONValue {
        var out: [String: JSONValue] = ["available": false]
        let home = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeNameKey]),
           let total = values.volumeTotalCapacity {
            let free = values.volumeAvailableCapacityForImportantUsage.map(Double.init) ?? Double(values.volumeAvailableCapacity ?? 0)
            let totalBytes = Double(total)
            out = [
                "available": true,
                "totalBytes": .number(totalBytes),
                "freeBytes": .number(free),
                "usedBytes": .number(max(0, totalBytes - free)),
                "usage": .number(totalBytes > 0 ? max(0, totalBytes - free) / totalBytes : 0),
                "volume": .string(values.volumeName ?? "Macintosh HD"),
            ]
        }
        // Disk activity from the block storage drivers' cumulative counters ("where available").
        if let counters = readDiskCounters() {
            if let previous = previousDisk, time > previous.time {
                let dt = time - previous.time
                out["readBytesPerSec"] = .number(Double(counters.read &- previous.read) / dt)
                out["writeBytesPerSec"] = .number(Double(counters.write &- previous.write) / dt)
            } else {
                out["readBytesPerSec"] = .null
                out["writeBytesPerSec"] = .null
            }
            out["activityAvailable"] = true
            previousDisk = (counters.read, counters.write, time)
        } else {
            out["activityAvailable"] = false
        }
        return .object(out)
    }

    private func readDiskCounters() -> (read: UInt64, write: UInt64)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0, write: UInt64 = 0, found = false
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard let property = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let statistics = property as? [String: Any] else { continue }
            if let r = statistics["Bytes (Read)"] as? NSNumber { read &+= r.uint64Value; found = true }
            if let w = statistics["Bytes (Write)"] as? NSNumber { write &+= w.uint64Value; found = true }
        }
        return found ? (read, write) : nil
    }

    // MARK: Network

    private func readNetwork(time: Double) -> JSONValue {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return ["available": false] }
        defer { freeifaddrs(head) }

        var interfaces: [String: [String: JSONValue]] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = cursor {
            let entry = pointer.pointee
            cursor = entry.ifa_next
            let name = String(cString: entry.ifa_name)
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_LOOPBACK == 0, let address = entry.ifa_addr else { continue }
            let isUp = flags & IFF_UP != 0 && flags & IFF_RUNNING != 0
            switch Int32(address.pointee.sa_family) {
            case AF_LINK:
                guard let data = entry.ifa_data else { continue }
                let counters = data.assumingMemoryBound(to: if_data.self).pointee
                // The kernel's per-interface counters are 32-bit; accumulate wrapped deltas into 64-bit totals.
                let current = (rx: counters.ifi_ibytes, tx: counters.ifi_obytes)
                if let previous = networkTotals[name] {
                    accumulatedRx &+= UInt64(current.rx &- previous.rx)
                    accumulatedTx &+= UInt64(current.tx &- previous.tx)
                }
                networkTotals[name] = current
                interfaces[name, default: [:]]["up"] = .bool(isUp)
            case AF_INET:
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    interfaces[name, default: [:]]["address"] = .string(String(cString: host))
                    interfaces[name, default: [:]]["up"] = .bool(isUp)
                }
            default: continue
            }
        }

        var down: JSONValue = .null, up: JSONValue = .null
        if let previous = previousNetwork, time > previous.time {
            let dt = time - previous.time
            let d = Double(accumulatedRx &- previous.rx) / dt
            let u = Double(accumulatedTx &- previous.tx) / dt
            down = .number(d); up = .number(u)
            downHistory.append(d); upHistory.append(u)
        }
        previousNetwork = (accumulatedRx, accumulatedTx, time)

        let active = interfaces.filter { $0.value["address"] != nil && $0.value["up"]?.boolValue == true }.sorted { $0.key < $1.key }
        let primary = active.first { $0.key.hasPrefix("en") } ?? active.first
        return [
            "available": true,
            "connected": .bool(!active.isEmpty),
            "downBytesPerSec": down,
            "upBytesPerSec": up,
            "primaryInterface": .string(primary?.key ?? ""),
            "address": primary?.value["address"] ?? "",
            "interfaces": .array(active.map { ["name": .string($0.key), "address": $0.value["address"] ?? ""] }),
            "downHistory": downHistory.json,
            "upHistory": upHistory.json,
        ]
    }

    // MARK: Battery

    private func readBattery(time: Double) -> JSONValue {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return ["available": true, "present": false, "source": "AC Power"]
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let current = (description[kIOPSCurrentCapacityKey] as? Double) ?? 0
            let maximum = (description[kIOPSMaxCapacityKey] as? Double) ?? 100
            let level = maximum > 0 ? current / maximum : 0
            let state = (description[kIOPSPowerSourceStateKey] as? String) ?? ""
            let charging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            let charged = (description[kIOPSIsChargedKey] as? Bool) ?? false
            let toEmpty = (description[kIOPSTimeToEmptyKey] as? Int) ?? -1
            let toFull = (description[kIOPSTimeToFullChargeKey] as? Int) ?? -1
            if time - lastBatterySample >= 60 || batteryHistory.values.isEmpty {
                batteryHistory.append(level)
                lastBatterySample = time
            }
            return [
                "available": true,
                "present": true,
                "level": .number(level),
                "charging": .bool(charging),
                "charged": .bool(charged),
                "source": .string(state == kIOPSACPowerValue ? "AC Power" : "Battery"),
                "onBattery": .bool(state == kIOPSBatteryPowerValue),
                "minutesRemaining": toEmpty >= 0 && !charging ? .number(Double(toEmpty)) : .null,
                "minutesToFull": toFull >= 0 && charging ? .number(Double(toFull)) : .null,
                "history": batteryHistory.json,
            ]
        }
        // Desktop Macs have no internal battery; say so instead of inventing a percentage.
        return ["available": true, "present": false, "source": "AC Power", "level": .null, "charging": false, "onBattery": false, "history": []]
    }

    // MARK: System

    private func readSystem() -> JSONValue {
        let info = ProcessInfo.processInfo
        let v = info.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return [
            "uptimeSeconds": .number(SystemMetricsCollector.uptime()),
            "hostname": .string(info.hostName),
            "osVersion": .string("macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"),
            "architecture": .string(architecture),
            "model": .string(SystemMetricsCollector.sysctlString("hw.model") ?? ""),
            "processor": .string(SystemMetricsCollector.sysctlString("machdep.cpu.brand_string") ?? architecture),
            "cores": .number(Double(info.processorCount)),
            "activeCores": .number(Double(info.activeProcessorCount)),
            "memoryBytes": .number(Double(info.physicalMemory)),
            "thermalState": .string(["nominal", "fair", "serious", "critical"][min(3, max(0, info.thermalState.rawValue))]),
            "lowPowerMode": .bool(info.isLowPowerModeEnabled),
        ]
    }

    /// Wall-clock time since boot (includes sleep), from `kern.boottime`.
    static func uptime() -> Double {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return ProcessInfo.processInfo.systemUptime }
        return Date().timeIntervalSince1970 - Double(boot.tv_sec)
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

/// Resource usage of this process, for the diagnostics panel.
enum ProcessMetrics {
    /// Resident memory in bytes (phys_footprint, the figure Activity Monitor shows).
    static func memoryFootprint() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) : nil
    }

    /// Total CPU seconds (user + system) consumed by this process so far.
    static func cpuTime() -> Double? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }
}
#endif
