import AppKit
import Foundation
import MFCore
import MFUtilities

// PRIVATE / UNSUPPORTED: this adapter is the only place in MagicForge that touches Apple's
// private MultitouchSupport.framework (through `MultitouchBridge`). It can stop working in any
// macOS update; the app must treat it as optional.

private final class WeakAdapterBox {
    weak var adapter: MultitouchSupportAdapter?
    init(_ adapter: MultitouchSupportAdapter) { self.adapter = adapter }
}

/// C callbacks cannot capture context, so the single contact-frame callback routes frames
/// through this process-wide table keyed by the device pointer.
private let streamRegistry = Locked<[UnsafeMutableRawPointer: WeakAdapterBox]>([:])

/// The one C callback registered with every started device.
private let contactFrameCallback: MTContactFrameCallback = { device, touches, count, timestamp, _ in
    guard let device = device else { return 0 }
    let target: MultitouchSupportAdapter? = streamRegistry.withLock { table in table[device]?.adapter }
    target?.handleFrame(device: device, touches: touches, count: Int(count), reportedTimestamp: timestamp)
    return 0
}

/// Streams raw finger contacts of Magic Mouse devices via the PRIVATE MultitouchSupport.framework.
///
/// - Only devices classified as Magic Mouse are started (see `MultitouchDeviceClassifier`);
///   built-in and external trackpads are left alone unless `includeAllDevicesForDiagnostics` is set.
/// - `onFrame` is called on the framework's own callback thread, outside every lock of this
///   class. Do not call `stop()` from inside `onFrame`. One frame that was already in flight
///   may still be delivered right after `stop()` returns.
/// - `start` throws `AdapterError.noDevice` when no Magic Mouse is connected; once running, the
///   adapter stays armed across disconnects and picks devices up again in `devicesDidChange()`.
public final class MultitouchSupportAdapter: TouchInputAdapter, @unchecked Sendable {
    public let identifier: String = "multitouch-support"
    public let displayName: String = "Multitouch (private MultitouchSupport.framework)"
    public let usesPrivateAPI: Bool = true
    /// `maxContacts` is a conservative figure for the Magic Mouse sensor (unverified on hardware).
    public let capabilities = InputCapabilities(rawContacts: true, maxContacts: 5, contactSize: true,
                                                pointerEvents: false)

    /// Updated for every Magic Mouse frame with a finger on the surface; wire
    /// `EventTapPointerSource.magicMouseActivityProbe` to `activity.isActive()`.
    public let activity = MagicMouseActivity()

    private static let maximumTouchesPerFrame = 32
    private static let log = Log("multitouch")

    private struct Stream {
        let description: MultitouchDeviceDescription
        let frameDeviceID: UInt64
        let isMagicMouse: Bool
        var tracker = ContactTracker()
    }

    /// Serializes start / stop / re-enumeration. Never taken by the frame callback.
    private let lifecycleLock = NSRecursiveLock()
    /// Guards the fields below; held only briefly, never while calling into the framework.
    private let stateLock = NSLock()
    private var onFrame: ((TouchFrame) -> Void)?
    private var streams: [UnsafeMutableRawPointer: Stream] = [:]
    private var lastTimestamp: TimeInterval = 0
    private var includeAllDevices = false
    private var invertYAxis = false

    // Guarded by lifecycleLock.
    private var deviceList: MultitouchDeviceList?
    private var running = false
    private var generation = 0
    private var wakeObserver: NSObjectProtocol?
    private let workQueue = DispatchQueue(label: "com.magicforge.multitouch.lifecycle")

    public init() {}

    deinit { stop() }

    /// Diagnostics only (`mfprobe --all-devices`): also stream trackpads. Set before `start`.
    public var includeAllDevicesForDiagnostics: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return includeAllDevices }
        set { stateLock.lock(); includeAllDevices = newValue; stateLock.unlock() }
    }

    /// The framework is assumed to report normalized y = 0 at the rear edge and 1 at the front
    /// edge (as it does for trackpads). If hardware testing shows the opposite for a model, set this.
    public var invertY: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return invertYAxis }
        set { stateLock.lock(); invertYAxis = newValue; stateLock.unlock() }
    }

    public var isRunning: Bool {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        return running
    }

    /// Devices currently being streamed.
    public var activeDevices: [MultitouchDeviceDescription] {
        stateLock.lock(); defer { stateLock.unlock() }
        return streams.values.map { $0.description }.sorted { $0.index < $1.index }
    }

    // MARK: TouchInputAdapter

    public func checkAvailability() -> AdapterAvailability {
        let bridge = MultitouchBridge.shared
        if let reason = bridge.unavailableReason { return .unavailable(reason: reason) }
        guard let list = bridge.copyDeviceList(), !selectDevices(from: list).isEmpty else {
            return .unavailable(reason: "No Magic Mouse multitouch device is connected")
        }
        return .available
    }

    public func start(onFrame: @escaping (TouchFrame) -> Void) throws {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        let bridge = MultitouchBridge.shared
        if let reason = bridge.unavailableReason { throw AdapterError.unavailable(reason) }
        if running {
            stateLock.lock(); self.onFrame = onFrame; stateLock.unlock()
            return
        }
        guard let list = bridge.copyDeviceList() else { throw AdapterError.noDevice }
        let selected = selectDevices(from: list)
        guard !selected.isEmpty else { throw AdapterError.noDevice }
        stateLock.lock(); self.onFrame = onFrame; stateLock.unlock()
        attach(selected, list: list)
        running = true
        generation += 1
        installWakeObserver()
        MultitouchSupportAdapter.log.notice("Started \(selected.count) multitouch stream(s)")
    }

    public func stop() {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        guard running else { return }
        running = false
        generation += 1
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
        detachAll()
        stateLock.lock(); onFrame = nil; stateLock.unlock()
        MultitouchSupportAdapter.log.notice("Stopped multitouch streams")
    }

    public func devicesDidChange() {
        lifecycleLock.lock()
        let isRunning = running
        let expected = generation
        lifecycleLock.unlock()
        guard isRunning else { return }
        // The multitouch device can appear a little later than the HID device, so re-check a few times.
        let delays: [TimeInterval] = [0, 0.5, 1.5, 3.5]
        for delay in delays {
            workQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.reconcile(expectedGeneration: expected, force: false)
            }
        }
    }

    // MARK: Device management (lifecycleLock held)

    private func selectDevices(from list: MultitouchDeviceList) -> [(ref: MTDeviceRef, description: MultitouchDeviceDescription)] {
        let includeAll: Bool = includeAllDevicesForDiagnostics
        var result: [(ref: MTDeviceRef, description: MultitouchDeviceDescription)] = []
        for (index, ref) in list.refs.enumerated() {
            let description = MultitouchBridge.shared.describe(ref, index: index)
            if includeAll || description.deviceClass == .magicMouse {
                result.append((ref: ref, description: description))
            }
        }
        return result
    }

    private func attach(_ selected: [(ref: MTDeviceRef, description: MultitouchDeviceDescription)],
                        list: MultitouchDeviceList) {
        let bridge = MultitouchBridge.shared
        guard let register = bridge.registerContactFrameCallback, let startDevice = bridge.deviceStart else { return }
        deviceList = list
        for entry in selected {
            let stream = Stream(description: entry.description,
                                frameDeviceID: entry.description.deviceID ?? UInt64(entry.description.index + 1),
                                isMagicMouse: entry.description.deviceClass == .magicMouse)
            stateLock.lock(); streams[entry.ref] = stream; stateLock.unlock()
            let box = WeakAdapterBox(self)
            streamRegistry.withLock { table in table[entry.ref] = box }
            register(entry.ref, contactFrameCallback)
            // The return value is not trusted: older headers declare MTDeviceStart as void.
            _ = startDevice(entry.ref, 0)
            if let isRunning = bridge.deviceIsRunning, !isRunning(entry.ref) {
                MultitouchSupportAdapter.log.notice("Multitouch device \(entry.description.index) does not report running after start")
            }
        }
    }

    /// Unregisters and stops every stream, releases the device list and reports contacts that
    /// were still down as cancelled.
    private func detachAll() {
        let bridge = MultitouchBridge.shared
        stateLock.lock()
        let old = streams
        streams = [:]
        let deliver = onFrame
        let timestamp: TimeInterval = max(MonotonicClock.now(), lastTimestamp)
        var cancelled: [TouchFrame] = []
        for (_, stream) in old {
            var tracker = stream.tracker
            if let frame = tracker.cancelAll(timestamp: timestamp, deviceID: stream.frameDeviceID) {
                cancelled.append(frame)
            }
        }
        if !cancelled.isEmpty { lastTimestamp = timestamp }
        stateLock.unlock()

        for ref in old.keys {
            streamRegistry.withLock { table in table[ref] = nil }
            if let unregister = bridge.unregisterContactFrameCallback { unregister(ref, contactFrameCallback) }
            if let stopDevice = bridge.deviceStop { _ = stopDevice(ref) }
        }
        // Dropping the array releases the device objects it owns (MTDeviceRelease is not called
        // on them separately, which would over-release).
        deviceList = nil
        if let deliver = deliver {
            for frame in cancelled { deliver(frame) }
        }
    }

    private func reconcile(expectedGeneration: Int, force: Bool) {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        guard running, generation == expectedGeneration else { return }
        let list: MultitouchDeviceList? = MultitouchBridge.shared.copyDeviceList()
        var selected: [(ref: MTDeviceRef, description: MultitouchDeviceDescription)] = []
        if let list = list { selected = selectDevices(from: list) }
        if !force {
            stateLock.lock()
            let current: [UInt64?] = streams.values.map { $0.description.deviceID }
            stateLock.unlock()
            let incoming: [UInt64?] = selected.map { $0.description.deviceID }
            let currentIDs = Set(current.compactMap { $0 })
            let incomingIDs = Set(incoming.compactMap { $0 })
            let allIdentified = currentIDs.count == current.count && incomingIDs.count == incoming.count
            // Same physical devices as before: keep the running streams and drop the new list.
            if allIdentified && currentIDs == incomingIDs { return }
        }
        detachAll()
        if let list = list, !selected.isEmpty { attach(selected, list: list) }
        MultitouchSupportAdapter.log.notice("Multitouch devices changed: now streaming \(selected.count)")
    }

    /// Streams are known to go quiet after sleep; restart them shortly after wake.
    private func installWakeObserver() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            self.lifecycleLock.lock()
            let expected = self.generation
            self.lifecycleLock.unlock()
            self.workQueue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.reconcile(expectedGeneration: expected, force: true)
            }
        }
    }

    // MARK: Frame handling (framework callback thread)

    func handleFrame(device: UnsafeMutableRawPointer, touches: UnsafeMutableRawPointer?, count: Int,
                     reportedTimestamp: Double) {
        guard count >= 0, count <= MultitouchSupportAdapter.maximumTouchesPerFrame else { return }
        let now: TimeInterval = MonotonicClock.now()

        stateLock.lock()
        guard var stream = streams[device], let deliver = onFrame else {
            stateLock.unlock()
            return
        }
        var raw: [RawTouch] = []
        if count > 0, let touches = touches {
            let typed: UnsafeMutablePointer<MTTouch> = touches.assumingMemoryBound(to: MTTouch.self)
            raw.reserveCapacity(count)
            var index = 0
            while index < count {
                raw.append(TouchConversion.rawTouch(from: typed[index], invertY: invertYAxis))
                index += 1
            }
        }
        let timestamp = TouchConversion.timestamp(reported: reportedTimestamp, now: now, previous: lastTimestamp)
        let frame: TouchFrame? = stream.tracker.frame(from: raw, timestamp: timestamp, deviceID: stream.frameDeviceID)
        if frame != nil { lastTimestamp = timestamp }
        let fingerDown: Bool = stream.tracker.hasContacts && stream.isMagicMouse
        streams[device] = stream
        stateLock.unlock()

        if fingerDown { activity.noteTouch(at: now) }
        if let frame = frame { deliver(frame) }
    }
}
