import Foundation
import IOKit
import IOKit.hid
import MFCore
import MFUtilities

private let hidDeviceMatched: IOHIDDeviceCallback = { context, _, _, device in
    guard let context = context else { return }
    Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue().deviceAppeared(device)
}

private let hidDeviceRemoved: IOHIDDeviceCallback = { context, _, _, device in
    guard let context = context else { return }
    Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue().deviceDisappeared(device)
}

/// Watches for Magic Mouse connect / disconnect with `IOHIDManager` (public IOKit API).
///
/// - Matching: all HID devices with Apple's USB (0x05AC) or Bluetooth (0x004C) vendor id; Magic
///   Mouse product ids (and names) are filtered in `HIDDeviceProperties.record(for:)`.
/// - The manager and its devices are NEVER opened (neither `IOHIDManagerOpen` nor
///   `IOHIDDeviceOpen`) and no input-value or report callbacks are registered. Enumeration and
///   property reads work without opening, so the mouse is never seized and the Input Monitoring
///   permission is not involved.
/// - A physical mouse exposes several HID interfaces; they are merged into one `DeviceInfo`.
/// - Matching / removal callbacks are scheduled on the main run loop, so `onChange` always runs
///   on the main thread. Call `start` / `stop` from the main thread.
public final class HIDDeviceMonitor: DeviceMonitoring {
    private static let log = Log("devices")
    /// How often battery levels are re-read while running.
    public static let batteryRefreshInterval: TimeInterval = 120

    private struct State {
        var manager: IOHIDManager?
        var interfaces: [IOHIDDevice: HIDInterfaceRecord] = [:]
        var devices: [DeviceInfo] = []
        var onChange: (([DeviceInfo]) -> Void)?
        var batteryTimer: DispatchSourceTimer?
    }

    private struct Change {
        var devices: [DeviceInfo]
        var handler: (([DeviceInfo]) -> Void)?
    }

    private let state = Locked<State>(State())

    public init() {}

    deinit { stop() }

    public var devices: [DeviceInfo] { state.withLock { $0.devices } }

    public func start(onChange: @escaping ([DeviceInfo]) -> Void) {
        let alreadyRunning: Bool = state.withLock { current -> Bool in
            current.onChange = onChange
            return current.manager != nil
        }
        if alreadyRunning { return }

        let manager: IOHIDManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, HIDDeviceProperties.matchingDictionaries)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, hidDeviceRemoved, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        // Synchronous first enumeration so `devices` is correct as soon as `start` returns.
        var initial: [IOHIDDevice: HIDInterfaceRecord] = [:]
        for device in HIDDeviceMonitor.copyDevices(of: manager) {
            if let record = HIDDeviceProperties.record(for: device) { initial[device] = record }
        }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + HIDDeviceMonitor.batteryRefreshInterval,
                       repeating: HIDDeviceMonitor.batteryRefreshInterval)
        timer.setEventHandler { [weak self] in self?.refreshBatteryLevels() }
        let snapshot: [DeviceInfo] = state.withLock { current -> [DeviceInfo] in
            current.manager = manager
            current.interfaces = initial
            current.devices = HIDDeviceGrouping.devices(from: Array(initial.values))
            current.batteryTimer = timer
            return current.devices
        }
        timer.resume()
        HIDDeviceMonitor.log.notice("Device monitor started, \(snapshot.count) Magic Mouse device(s) present")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let change: Change = self.state.withLock { current -> Change in
                let handler: (([DeviceInfo]) -> Void)? = current.manager == nil ? nil : current.onChange
                return Change(devices: current.devices, handler: handler)
            }
            change.handler?(change.devices)
        }
    }

    public func stop() {
        let previous: State = state.withLock { current -> State in
            let result = current
            current = State()
            return result
        }
        previous.batteryTimer?.cancel()
        guard let manager = previous.manager else { return }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        HIDDeviceMonitor.log.notice("Device monitor stopped")
    }

    /// Re-reads the battery level of every known device and reports a change, if any.
    public func refreshBatteryLevels() {
        let update: Change? = state.withLock { current -> Change? in
            guard current.manager != nil else { return nil }
            for (device, record) in current.interfaces {
                var updated = record
                updated.batteryPercent = HIDDeviceProperties.batteryPercent(for: device)
                current.interfaces[device] = updated
            }
            let devices = HIDDeviceGrouping.devices(from: Array(current.interfaces.values))
            guard devices != current.devices else { return nil }
            current.devices = devices
            return Change(devices: devices, handler: current.onChange)
        }
        guard let update = update, let handler = update.handler else { return }
        if Thread.isMainThread {
            handler(update.devices)
        } else {
            DispatchQueue.main.async { handler(update.devices) }
        }
    }

    /// One-shot enumeration without callbacks or a run loop (used by `mfprobe`).
    public static func snapshot() -> [DeviceInfo] {
        let manager: IOHIDManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, HIDDeviceProperties.matchingDictionaries)
        var records: [HIDInterfaceRecord] = []
        for device in copyDevices(of: manager) {
            if let record = HIDDeviceProperties.record(for: device) { records.append(record) }
        }
        return HIDDeviceGrouping.devices(from: records)
    }

    private static func copyDevices(of manager: IOHIDManager) -> [IOHIDDevice] {
        let copied: CFSet? = IOHIDManagerCopyDevices(manager)
        guard let set = copied as? Set<IOHIDDevice> else { return [] }
        return Array(set)
    }

    // MARK: IOHIDManager callbacks (main run loop)

    fileprivate func deviceAppeared(_ device: IOHIDDevice) {
        guard let record = HIDDeviceProperties.record(for: device) else { return }
        publish { current in current.interfaces[device] = record }
    }

    fileprivate func deviceDisappeared(_ device: IOHIDDevice) {
        publish { current in current.interfaces[device] = nil }
    }

    private func publish(_ mutate: (inout State) -> Void) {
        let update: Change? = state.withLock { current -> Change? in
            guard current.manager != nil else { return nil }
            mutate(&current)
            let devices = HIDDeviceGrouping.devices(from: Array(current.interfaces.values))
            guard devices != current.devices else { return nil }
            current.devices = devices
            return Change(devices: devices, handler: current.onChange)
        }
        if let update = update { update.handler?(update.devices) }
    }
}
