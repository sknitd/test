import Foundation

/// What kind of multitouch surface a MultitouchSupport device is believed to be.
public enum MultitouchDeviceClass: String, Sendable, Equatable {
    case magicMouse, builtInTrackpad, externalTrackpad, unknown
}

/// Static properties of one device reported by the PRIVATE MultitouchSupport.framework.
/// Every property is nil when the corresponding private function is missing or failed.
public struct MultitouchDeviceDescription: Sendable, Equatable {
    public var index: Int
    public var deviceID: UInt64?
    public var familyID: Int?
    public var isBuiltIn: Bool?
    public var isRunning: Bool?
    /// Sensor surface size in millimetres (the framework reports 1/100 mm).
    public var surfaceWidthMM: Double?
    public var surfaceHeightMM: Double?
    public var deviceClass: MultitouchDeviceClass = .unknown
    /// Which rule produced `deviceClass` (shown by `mfprobe`).
    public var classificationReason: String = ""

    public init(index: Int) { self.index = index }
}

/// Decides whether a MultitouchSupport device is a Magic Mouse.
///
/// Rules, in order (all based on community observations, none documented by Apple):
/// 1. `MTDeviceIsBuiltIn` true → built-in trackpad.
/// 2. Family id 112 or 113 → Magic Mouse (1st generation / Magic Mouse 2). The id of the 2024
///    USB-C model has not been confirmed, which is why rule 4 exists.
/// 3. Family id 128, 129 or 130 → external Magic Trackpad.
/// 4. Surface shape: a Magic Mouse sensor is a narrow portrait strip (about 52 × 90 mm) while
///    every trackpad is landscape and at least 100 mm wide.
/// 5. Otherwise unknown; unknown devices are never streamed outside diagnostics mode.
public enum MultitouchDeviceClassifier {
    public static let magicMouseFamilyIDs: Set<Int> = [112, 113]
    public static let externalTrackpadFamilyIDs: Set<Int> = [128, 129, 130]

    public static func classify(isBuiltIn: Bool?, familyID: Int?, widthMM: Double?,
                                heightMM: Double?) -> (deviceClass: MultitouchDeviceClass, reason: String) {
        if isBuiltIn == true { return (.builtInTrackpad, "MTDeviceIsBuiltIn is true") }
        if let familyID = familyID {
            if magicMouseFamilyIDs.contains(familyID) { return (.magicMouse, "family id \(familyID)") }
            if externalTrackpadFamilyIDs.contains(familyID) { return (.externalTrackpad, "family id \(familyID)") }
        }
        if let width = widthMM, let height = heightMM, width > 0, height > 0 {
            let isPortraitStrip = height >= width * 1.2 && width >= 30 && width <= 75 && height >= 60 && height <= 130
            if isPortraitStrip { return (.magicMouse, "portrait sensor surface, not built in") }
            if width > height {
                return (isBuiltIn == nil ? .unknown : .externalTrackpad, "landscape sensor surface")
            }
        }
        return (.unknown, "no rule matched")
    }
}

/// Read-only inspection of the private multitouch stack for `mfprobe` and the Devices screen.
/// Never starts a device stream and never triggers a permission prompt.
public enum MultitouchDiagnostics {
    public struct Symbol: Sendable, Equatable {
        public var name: String
        public var isRequired: Bool
        public var isResolved: Bool
    }

    public struct Report: Sendable, Equatable {
        public var frameworkPath: String
        public var frameworkLoaded: Bool
        public var loadError: String?
        public var symbols: [Symbol]
        public var touchStride: Int
        public var expectedTouchStride: Int
        /// Nil when the Swift mirror of the touch struct has the expected layout.
        public var layoutProblem: String?
        /// Nil when the adapter could stream (devices permitting).
        public var unavailableReason: String?
        public var devices: [MultitouchDeviceDescription]
    }

    public static func collect() -> Report {
        let bridge = MultitouchBridge.shared
        var devices: [MultitouchDeviceDescription] = []
        if let list = bridge.copyDeviceList() {
            for (index, ref) in list.refs.enumerated() {
                devices.append(bridge.describe(ref, index: index))
            }
        }
        return Report(
            frameworkPath: MultitouchBridge.frameworkPath,
            frameworkLoaded: bridge.isLoaded,
            loadError: bridge.loadError,
            symbols: bridge.symbols.map { Symbol(name: $0.name, isRequired: $0.isRequired, isResolved: $0.isResolved) },
            touchStride: MemoryLayout<MTTouch>.stride,
            expectedTouchStride: MTTouchLayout.expectedStride,
            layoutProblem: MTTouchLayout.validate(),
            unavailableReason: bridge.unavailableReason,
            devices: devices
        )
    }
}
