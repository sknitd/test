import CoreFoundation
import Foundation

/// `mfprobe --self-check`: everything that can be learned without touching a device.
enum SelfCheck {
    static let jsonBeginMarker = "-----BEGIN MFPROBE JSON-----"
    static let jsonEndMarker = "-----END MFPROBE JSON-----"

    static func run(attemptTap: Bool) -> Int32 {
        let report = MultitouchDiagnostics.collect()
        let hidDevices = HIDDeviceMonitor.snapshot()
        let accessibilityTrusted: Bool = AXIsProcessTrusted()
        let canListen: Bool = CGPreflightListenEventAccess()
        let canPost: Bool = CGPreflightPostEventAccess()
        let availability = MultitouchSupportAdapter().checkAvailability()

        var tap: [String: Any] = [:]
        if attemptTap || canListen || accessibilityTrusted {
            tap["attempted"] = true
            tap["listenOnlyCreated"] = canCreateTap(options: .listenOnly)
            tap["activeCreated"] = canCreateTap(options: .defaultTap)
        } else {
            tap["attempted"] = false
            tap["reason"] = "no Accessibility / Input Monitoring permission; pass --attempt-tap to try anyway"
        }

        var availabilityText = "available"
        if case .unavailable(let reason) = availability { availabilityText = "unavailable: \(reason)" }

        let version = ProcessInfo.processInfo.operatingSystemVersion
        let json: [String: Any] = [
            "tool": "mfprobe",
            "mode": "self-check",
            "os": [
                "versionString": ProcessInfo.processInfo.operatingSystemVersionString,
                "major": version.majorVersion,
                "minor": version.minorVersion,
                "patch": version.patchVersion,
                "architecture": architecture(),
            ] as [String: Any],
            "multitouchSupport": [
                "frameworkPath": report.frameworkPath,
                "loaded": report.frameworkLoaded,
                "loadError": report.loadError ?? "",
                "symbols": report.symbols.map { symbol -> [String: Any] in
                    ["name": symbol.name, "required": symbol.isRequired, "resolved": symbol.isResolved]
                },
                "touchStride": report.touchStride,
                "expectedTouchStride": report.expectedTouchStride,
                "layoutProblem": report.layoutProblem ?? "",
                "unavailableReason": report.unavailableReason ?? "",
                "adapterAvailability": availabilityText,
                "deviceCount": report.devices.count,
                "devices": report.devices.map { deviceJSON($0) },
            ] as [String: Any],
            "hid": [
                "magicMouseCount": hidDevices.count,
                "devices": hidDevices.map { hidJSON($0) },
            ] as [String: Any],
            "permissions": [
                "accessibilityTrusted": accessibilityTrusted,
                "listenEventAccess": canListen,
                "postEventAccess": canPost,
            ] as [String: Any],
            "eventTap": tap,
        ]

        printSummary(report: report, hidDevices: hidDevices, availability: availabilityText,
                     accessibilityTrusted: accessibilityTrusted, canListen: canListen, canPost: canPost, tap: tap)

        guard JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            ProbeOutput.error("Internal error: could not encode the self-check report as JSON\n")
            return 1
        }
        print(jsonBeginMarker)
        print(text)
        print(jsonEndMarker)
        return 0
    }

    static func deviceJSON(_ device: MultitouchDeviceDescription) -> [String: Any] {
        var json: [String: Any] = [
            "index": device.index,
            "class": device.deviceClass.rawValue,
            "classificationReason": device.classificationReason,
        ]
        if let deviceID = device.deviceID { json["deviceID"] = String(deviceID) }
        if let familyID = device.familyID { json["familyID"] = familyID }
        if let isBuiltIn = device.isBuiltIn { json["builtIn"] = isBuiltIn }
        if let isRunning = device.isRunning { json["running"] = isRunning }
        if let width = device.surfaceWidthMM { json["surfaceWidthMM"] = width }
        if let height = device.surfaceHeightMM { json["surfaceHeightMM"] = height }
        return json
    }

    static func hidJSON(_ device: DeviceInfo) -> [String: Any] {
        var json: [String: Any] = [
            "name": device.name,
            "model": device.model.rawValue,
            "vendorID": String(format: "0x%04X", device.vendorID),
            "productID": String(format: "0x%04X", device.productID),
            "transport": device.transport,
        ]
        if let battery = device.batteryPercent { json["batteryPercent"] = battery }
        return json
    }

    private static func architecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    /// Creates a tap for scroll events and immediately invalidates it. No event is ever handled.
    private static func canCreateTap(options: CGEventTapOptions) -> Bool {
        let mask: CGEventMask = CGEventMask(1) << CGEventMask(CGEventType.scrollWheel.rawValue)
        let callback: CGEventTapCallBack = { (_: CGEventTapProxy, _: CGEventType, event: CGEvent,
                                              _: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? in
            Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: options,
                                           eventsOfInterest: mask, callback: callback, userInfo: nil) else {
            return false
        }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        return true
    }

    private static func printSummary(report: MultitouchDiagnostics.Report, hidDevices: [DeviceInfo],
                                     availability: String, accessibilityTrusted: Bool, canListen: Bool,
                                     canPost: Bool, tap: [String: Any]) {
        print("mfprobe self-check")
        print("  macOS: \(ProcessInfo.processInfo.operatingSystemVersionString) (\(architecture()))")
        print("  MultitouchSupport.framework loaded: \(report.frameworkLoaded)")
        if let error = report.loadError { print("    load error: \(error)") }
        for symbol in report.symbols {
            let status = symbol.isResolved ? "ok     " : "MISSING"
            print("    \(status) \(symbol.name)\(symbol.isRequired ? " (required)" : "")")
        }
        print("  Touch struct stride: \(report.touchStride) (expected \(report.expectedTouchStride))")
        if let problem = report.layoutProblem { print("    layout problem: \(problem)") }
        print("  Multitouch devices: \(report.devices.count)")
        for device in report.devices { print("    " + DeviceListing.line(for: device)) }
        print("  Adapter availability: \(availability)")
        print("  HID Magic Mouse devices: \(hidDevices.count)")
        for device in hidDevices { print("    " + DeviceListing.line(for: device)) }
        print("  Accessibility trusted: \(accessibilityTrusted)")
        print("  Listen-event access (Input Monitoring): \(canListen)")
        print("  Post-event access: \(canPost)")
        if let attempted = tap["attempted"] as? Bool, attempted {
            print("  Event tap, listen-only: \(tap["listenOnlyCreated"] as? Bool ?? false)")
            print("  Event tap, active: \(tap["activeCreated"] as? Bool ?? false)")
        } else {
            print("  Event tap: not attempted (\(tap["reason"] as? String ?? ""))")
        }
        print("")
    }
}
