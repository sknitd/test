import CoreFoundation
import Foundation

/// `mfprobe --frames` and `mfprobe --gestures`: live streams for verification on real hardware.
enum StreamingProbe {
    enum Mode { case frames, gestures }

    /// Counters shared between the adapter's callback thread and the main thread.
    private struct Counters {
        var framesThisSecond = 0
        var totalFrames = 0
        var maxContacts = 0
        var gestures = 0
    }

    static func run(mode: Mode, duration: TimeInterval, allDevices: Bool, invertY: Bool) -> Int32 {
        let adapter = MultitouchSupportAdapter()
        adapter.includeAllDevicesForDiagnostics = allDevices
        adapter.invertY = invertY
        if case .unavailable(let reason) = adapter.checkAvailability() {
            print("Touch input is unavailable: \(reason)")
            return 2
        }

        let counters = Locked<Counters>(Counters())
        let engineLock = NSLock()
        let engine = GestureEngine(config: RecognizerConfig(), calibration: DeviceCalibration())
        engine.enabledKinds = Set(GestureKind.allCases.filter { $0.requirement == .rawContacts })

        do {
            try adapter.start { frame in
                let touching: Int = frame.touching.count
                counters.withLock { current in
                    current.framesThisSecond += 1
                    current.totalFrames += 1
                    current.maxContacts = max(current.maxContacts, touching)
                }
                switch mode {
                case .frames:
                    print(describe(frame))
                case .gestures:
                    engineLock.lock()
                    let events: [GestureEvent] = engine.process(frame)
                    engineLock.unlock()
                    report(events, counters: counters)
                }
            }
        } catch {
            print("Could not start the touch stream: \(error)")
            return 2
        }

        print("Streaming from \(adapter.activeDevices.count) device(s) for \(ProbeOutput.format(duration, digits: 0)) s. Touch the mouse surface; Control-C stops.")
        for device in adapter.activeDevices { print("  " + DeviceListing.line(for: device)) }

        let rateTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        rateTimer.schedule(deadline: .now() + 1, repeating: 1.0)
        rateTimer.setEventHandler {
            let rate: Int = counters.withLock { current -> Int in
                let value = current.framesThisSecond
                current.framesThisSecond = 0
                return value
            }
            if rate > 0 { print("-- \(rate) frames/s") }
        }
        rateTimer.resume()

        // Pending taps and holds complete on a deadline, not on a frame.
        let deadlineTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        deadlineTimer.schedule(deadline: .now() + 0.005, repeating: 0.005)
        deadlineTimer.setEventHandler {
            guard mode == .gestures else { return }
            let now: TimeInterval = MonotonicClock.now()
            engineLock.lock()
            var events: [GestureEvent] = []
            if let deadline = engine.nextDeadline, deadline <= now { events = engine.advance(to: now) }
            engineLock.unlock()
            report(events, counters: counters)
        }
        deadlineTimer.resume()

        let interrupted = ProbeRunLoop.run(for: duration)
        rateTimer.cancel()
        deadlineTimer.cancel()
        adapter.stop()

        let totals: Counters = counters.current
        print(interrupted ? "Interrupted." : "Finished.")
        print("Total frames: \(totals.totalFrames), most simultaneous contacts: \(totals.maxContacts)")
        if mode == .gestures { print("Gestures recognized: \(totals.gestures)") }
        if totals.totalFrames == 0 {
            print("No frames were received. Either the surface was not touched or the private framework does not deliver Magic Mouse contacts on this system.")
        }
        return 0
    }

    private static func report(_ events: [GestureEvent], counters: Locked<Counters>) {
        guard !events.isEmpty else { return }
        counters.withLock { current in current.gestures += events.count }
        for event in events {
            print("GESTURE \(event.kind.rawValue) fingers=\(event.fingerCount) confidence=\(ProbeOutput.format(event.confidence, digits: 2)) magnitude=\(ProbeOutput.format(event.magnitude, digits: 1)) duration=\(ProbeOutput.format(event.duration, digits: 3))s")
        }
    }

    private static func describe(_ frame: TouchFrame) -> String {
        var text = "t=\(ProbeOutput.format(frame.timestamp)) device=\(frame.deviceID) contacts=\(frame.touching.count)"
        for contact in frame.contacts {
            text += " | id=\(contact.id) \(contact.phase.rawValue) x=\(ProbeOutput.format(contact.x)) y=\(ProbeOutput.format(contact.y)) size=\(ProbeOutput.format(contact.size, digits: 2))"
        }
        return text
    }
}

/// Keeps the main run loop alive for a limited time and turns SIGINT into a clean exit.
enum ProbeRunLoop {
    /// Returns true when the run was ended by Control-C.
    static func run(for duration: TimeInterval) -> Bool {
        let interrupted = Locked<Bool>(false)
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: DispatchQueue.main)
        source.setEventHandler {
            interrupted.withLock { $0 = true }
            CFRunLoopStop(CFRunLoopGetMain())
        }
        source.resume()
        let end: TimeInterval = MonotonicClock.now() + duration
        while !interrupted.current {
            let remaining: TimeInterval = end - MonotonicClock.now()
            if remaining <= 0 { break }
            _ = CFRunLoopRunInMode(kCFRunLoopDefaultMode, min(remaining, 0.25), false)
        }
        source.cancel()
        signal(SIGINT, SIG_DFL)
        return interrupted.current
    }
}
