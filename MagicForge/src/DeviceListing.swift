import CoreFoundation
import Foundation

/// `mfprobe --devices`.
enum DeviceListing {
    static func run() -> Int32 {
        let hidDevices = HIDDeviceMonitor.snapshot()
        print("Magic Mouse HID devices (IOHIDManager, public API): \(hidDevices.count)")
        for device in hidDevices { print("  " + line(for: device)) }

        let report = MultitouchDiagnostics.collect()
        print("Multitouch devices (PRIVATE MultitouchSupport.framework): \(report.devices.count)")
        if let reason = report.unavailableReason { print("  adapter unavailable: \(reason)") }
        for device in report.devices { print("  " + line(for: device)) }
        return 0
    }

    static func line(for device: DeviceInfo) -> String {
        var text = "\(device.name) — \(device.model.displayName), "
        text += String(format: "vendor 0x%04X product 0x%04X", device.vendorID, device.productID)
        text += ", transport \(device.transport.isEmpty ? "unknown" : device.transport)"
        if let battery = device.batteryPercent { text += ", battery \(battery)%" }
        return text
    }

    static func line(for device: MultitouchDeviceDescription) -> String {
        var parts: [String] = ["#\(device.index)", "class \(device.deviceClass.rawValue) (\(device.classificationReason))"]
        if let familyID = device.familyID { parts.append("family \(familyID)") }
        if let isBuiltIn = device.isBuiltIn { parts.append("builtIn \(isBuiltIn)") }
        if let width = device.surfaceWidthMM, let height = device.surfaceHeightMM {
            parts.append("surface \(ProbeOutput.format(width, digits: 1)) x \(ProbeOutput.format(height, digits: 1)) mm")
        }
        if let deviceID = device.deviceID { parts.append("id \(deviceID)") }
        if let isRunning = device.isRunning { parts.append("running \(isRunning)") }
        return parts.joined(separator: ", ")
    }
}
