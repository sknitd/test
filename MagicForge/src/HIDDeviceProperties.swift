import CoreFoundation
import Foundation

// `IORegistryEntrySearchCFProperty` is imported either as a managed `CFTypeRef!` or as
// `Unmanaged<CFTypeRef>!` depending on the SDK's annotations; these overloads accept both.
private func managedValue(_ value: CFTypeRef?) -> CFTypeRef? { value }
private func managedValue(_ value: Unmanaged<CFTypeRef>?) -> CFTypeRef? { value?.takeRetainedValue() }

/// Reads identification properties of an `IOHIDDevice`. Only property lookups are performed: the
/// device is never opened, so no input reports are received and no TCC permission is involved.
enum HIDDeviceProperties {
    static func string(_ device: IOHIDDevice, _ key: String) -> String? {
        let value: CFTypeRef? = IOHIDDeviceGetProperty(device, cfstr(key))
        return value as? String
    }

    static func integer(_ device: IOHIDDevice, _ key: String) -> Int? {
        let value: CFTypeRef? = IOHIDDeviceGetProperty(device, cfstr(key))
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    /// Nil when the device is not a Magic Mouse.
    static func record(for device: IOHIDDevice) -> HIDInterfaceRecord? {
        guard let vendorID = integer(device, kIOHIDVendorIDKey),
              let productID = integer(device, kIOHIDProductIDKey) else { return nil }
        let productName: String = string(device, kIOHIDProductKey) ?? ""
        guard let model = MagicMouseIdentity.model(vendorID: vendorID, productID: productID,
                                                   productName: productName) else { return nil }
        let physicalID = HIDDeviceGrouping.physicalID(
            serialNumber: string(device, kIOHIDSerialNumberKey),
            bluetoothAddress: string(device, "DeviceAddress"),
            uniqueID: string(device, kIOHIDPhysicalDeviceUniqueIDKey),
            vendorID: vendorID, productID: productID,
            locationID: integer(device, kIOHIDLocationIDKey))
        return HIDInterfaceRecord(physicalID: physicalID,
                                  name: productName.isEmpty ? model.displayName : productName,
                                  model: model, vendorID: vendorID, productID: productID,
                                  transport: string(device, kIOHIDTransportKey) ?? "",
                                  batteryPercent: batteryPercent(for: device))
    }

    /// Best effort. Apple's HID drivers publish `BatteryPercent` (0…100) on the device's IORegistry
    /// entry or on a nearby driver object, so the device, then its registry children, then its
    /// parents are searched. Undocumented; nil when the property is not found.
    static func batteryPercent(for device: IOHIDDevice) -> Int? {
        let key = "BatteryPercent"
        if let direct = integer(device, key), (0...100).contains(direct) { return direct }
        let service: io_service_t = IOHIDDeviceGetService(device)
        guard service != 0 else { return nil }
        let recursive = IOOptionBits(kIORegistryIterateRecursively)
        let parents = IOOptionBits(kIORegistryIterateParents)
        let searches: [IOOptionBits] = [recursive, recursive | parents]
        for options in searches {
            let found: CFTypeRef? = managedValue(
                IORegistryEntrySearchCFProperty(service, kIOServicePlane, cfstr(key), kCFAllocatorDefault, options))
            if let number = found as? NSNumber, (0...100).contains(number.intValue) { return number.intValue }
        }
        return nil
    }

    /// Matching dictionaries for `IOHIDManagerSetDeviceMatchingMultiple`: every HID device of
    /// Apple's two vendor ids. Product filtering happens in `record(for:)` so that future Magic
    /// Mouse models can still be recognized by name.
    static var matchingDictionaries: CFArray {
        let dictionaries: [[String: Any]] = MagicMouseIdentity.vendorIDs.map { vendorID in
            [kIOHIDVendorIDKey: vendorID]
        }
        return cfarr(dictionaries)
    }
}
