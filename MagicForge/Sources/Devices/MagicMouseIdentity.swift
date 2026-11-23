import Foundation
import MFCore

/// USB / Bluetooth identity of the Magic Mouse family.
///
/// Product ids are the ones used by the Linux `hid-magicmouse` driver (`drivers/hid/hid-ids.h`):
/// 0x030D Magic Mouse (1st generation), 0x0269 Magic Mouse 2, 0x0323 Magic Mouse (USB-C, 2024).
/// Apple uses vendor id 0x05AC over USB and for the first generation over Bluetooth, and its
/// Bluetooth SIG company id 0x004C for newer models over Bluetooth.
public enum MagicMouseIdentity {
    public static let appleUSBVendorID = 0x05AC
    public static let appleBluetoothVendorID = 0x004C
    public static let vendorIDs: [Int] = [appleUSBVendorID, appleBluetoothVendorID]

    public static let magicMouse1ProductID = 0x030D
    public static let magicMouse2ProductID = 0x0269
    public static let magicMouseUSBCProductID = 0x0323
    public static let productIDs: [Int] = [magicMouse1ProductID, magicMouse2ProductID, magicMouseUSBCProductID]

    /// Nil when the device is not a Magic Mouse. An Apple device with an unknown product id whose
    /// product name contains "Magic Mouse" is accepted as `.unknownMagicMouse` (future models).
    public static func model(vendorID: Int, productID: Int, productName: String) -> MagicMouseModel? {
        guard vendorIDs.contains(vendorID) else { return nil }
        switch productID {
        case magicMouse1ProductID: return .magicMouse1
        case magicMouse2ProductID: return .magicMouse2
        case magicMouseUSBCProductID: return .magicMouseUSBC
        default:
            return productName.range(of: "Magic Mouse", options: .caseInsensitive) != nil ? .unknownMagicMouse : nil
        }
    }
}

/// What one HID interface told us about the physical mouse it belongs to.
struct HIDInterfaceRecord: Equatable {
    /// Identity of the physical device; equal for all HID interfaces of one mouse.
    var physicalID: String
    var name: String
    var model: MagicMouseModel
    var vendorID: Int
    var productID: Int
    var transport: String
    var batteryPercent: Int?
}

enum HIDDeviceGrouping {
    /// Stable identifier, in order of preference: serial number, Bluetooth address, the HID
    /// "physical device unique id", and finally vendor:product:location (not stable across ports).
    static func physicalID(serialNumber: String?, bluetoothAddress: String?, uniqueID: String?,
                           vendorID: Int, productID: Int, locationID: Int?) -> String {
        let candidates: [String?] = [serialNumber, bluetoothAddress, uniqueID]
        for candidate in candidates {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value.lowercased()
            }
        }
        let location: String = locationID.map { String($0, radix: 16) } ?? "0"
        return String(format: "%04x:%04x:", vendorID, productID) + location
    }

    /// Collapses the HID interfaces of each physical mouse into one `DeviceInfo`, sorted by name then id.
    static func devices(from records: [HIDInterfaceRecord]) -> [DeviceInfo] {
        var byID: [String: DeviceInfo] = [:]
        for record in records {
            if var existing = byID[record.physicalID] {
                if existing.batteryPercent == nil { existing.batteryPercent = record.batteryPercent }
                if existing.name.isEmpty { existing.name = record.name }
                if existing.transport.isEmpty { existing.transport = record.transport }
                byID[record.physicalID] = existing
            } else {
                byID[record.physicalID] = DeviceInfo(id: record.physicalID, name: record.name, model: record.model,
                                                     vendorID: record.vendorID, productID: record.productID,
                                                     transport: record.transport,
                                                     batteryPercent: record.batteryPercent, isConnected: true,
                                                     surface: .magicMouse)
            }
        }
        return byID.values.sorted { lhs, rhs in
            lhs.name == rhs.name ? lhs.id < rhs.id : lhs.name < rhs.name
        }
    }
}
