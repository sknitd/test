import Foundation

// PRIVATE / UNSUPPORTED
// ---------------------
// Runtime binding to Apple's private MultitouchSupport.framework. Nothing here is linked at build
// time: the framework is opened with `dlopen` and every function is looked up with `dlsym`, so
// the app launches (and reports the adapter as unavailable) when the framework or a symbol is
// missing. Signatures are the community's reverse-engineered ones; none is documented by Apple.

/// PRIVATE/UNSUPPORTED. Opaque `MTDeviceRef` (a CoreFoundation-style object).
typealias MTDeviceRef = UnsafeMutableRawPointer

/// PRIVATE/UNSUPPORTED. `int callback(MTDeviceRef device, MTTouch *touches, int count, double timestamp, int frame)`.
/// Some headers declare the return type as `void`; returning an `int` is harmless either way.
typealias MTContactFrameCallback = @convention(c) (
    _ device: UnsafeMutableRawPointer?, _ touches: UnsafeMutableRawPointer?, _ count: Int32,
    _ timestamp: Double, _ frame: Int32
) -> Int32

/// PRIVATE/UNSUPPORTED. Function table of MultitouchSupport.framework resolved at runtime.
final class MultitouchBridge {
    /// On macOS 11+ the binary lives in the dyld shared cache, so this path does not exist on disk;
    /// `dlopen` resolves it anyway. Never test for the file with FileManager.
    static let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    /// Loaded once per process and never closed.
    static let shared = MultitouchBridge()

    struct SymbolStatus {
        let name: String
        let isRequired: Bool
        let isResolved: Bool
    }

    typealias CreateListFn = @convention(c) () -> UnsafeMutableRawPointer?
    typealias CreateDefaultFn = @convention(c) () -> UnsafeMutableRawPointer?
    typealias RegisterCallbackFn = @convention(c) (UnsafeMutableRawPointer, MTContactFrameCallback) -> Void
    typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    typealias StopFn = @convention(c) (UnsafeMutableRawPointer) -> Int32
    typealias ReleaseFn = @convention(c) (UnsafeMutableRawPointer) -> Void
    typealias BoolQueryFn = @convention(c) (UnsafeMutableRawPointer) -> Bool
    typealias Int32QueryFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>) -> Int32
    typealias UInt64QueryFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    typealias DimensionsFn = @convention(c) (
        UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>
    ) -> Int32

    let isLoaded: Bool
    let loadError: String?

    /// `CFMutableArrayRef MTDeviceCreateList(void)` — returns a +1 retained array of MTDeviceRef.
    let createList: CreateListFn?
    /// `MTDeviceRef MTDeviceCreateDefault(void)` — resolved for diagnostics only.
    let createDefault: CreateDefaultFn?
    /// `void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction)`.
    let registerContactFrameCallback: RegisterCallbackFn?
    /// `void MTUnregisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction)`.
    let unregisterContactFrameCallback: RegisterCallbackFn?
    /// `OSStatus MTDeviceStart(MTDeviceRef, int mode)` (mode 0). Older headers declare `void`,
    /// so the returned value is never trusted.
    let deviceStart: StartFn?
    /// `OSStatus MTDeviceStop(MTDeviceRef)`.
    let deviceStop: StopFn?
    /// `void MTDeviceRelease(MTDeviceRef)` — resolved for diagnostics; devices obtained from
    /// `MTDeviceCreateList` are owned by the returned array and released with it.
    let deviceRelease: ReleaseFn?
    /// `bool MTDeviceIsRunning(MTDeviceRef)`.
    let deviceIsRunning: BoolQueryFn?
    /// `bool MTDeviceIsBuiltIn(MTDeviceRef)`.
    let deviceIsBuiltIn: BoolQueryFn?
    /// `OSStatus MTDeviceGetFamilyID(MTDeviceRef, int *)`.
    let deviceGetFamilyID: Int32QueryFn?
    /// `OSStatus MTDeviceGetDeviceID(MTDeviceRef, uint64_t *)`.
    let deviceGetDeviceID: UInt64QueryFn?
    /// `OSStatus MTDeviceGetSensorSurfaceDimensions(MTDeviceRef, int *width, int *height)` in 1/100 mm.
    let deviceGetSensorSurfaceDimensions: DimensionsFn?

    private(set) var symbols: [SymbolStatus] = []

    private init() {
        var statuses: [SymbolStatus] = []
        guard let handle = dlopen(MultitouchBridge.frameworkPath, RTLD_NOW) else {
            var message = "dlopen failed"
            if let error = dlerror() { message = String(cString: error) }
            isLoaded = false
            loadError = message
            createList = nil; createDefault = nil
            registerContactFrameCallback = nil; unregisterContactFrameCallback = nil
            deviceStart = nil; deviceStop = nil; deviceRelease = nil
            deviceIsRunning = nil; deviceIsBuiltIn = nil
            deviceGetFamilyID = nil; deviceGetDeviceID = nil; deviceGetSensorSurfaceDimensions = nil
            for (name, required) in MultitouchBridge.symbolTable {
                statuses.append(SymbolStatus(name: name, isRequired: required, isResolved: false))
            }
            symbols = statuses
            return
        }
        isLoaded = true
        loadError = nil

        func lookup<T>(_ name: String, required: Bool, as type: T.Type) -> T? {
            let address: UnsafeMutableRawPointer? = dlsym(handle, name)
            statuses.append(SymbolStatus(name: name, isRequired: required, isResolved: address != nil))
            guard let address = address else { return nil }
            return unsafeBitCast(address, to: type)
        }

        createList = lookup("MTDeviceCreateList", required: true, as: CreateListFn.self)
        registerContactFrameCallback = lookup("MTRegisterContactFrameCallback", required: true,
                                              as: RegisterCallbackFn.self)
        unregisterContactFrameCallback = lookup("MTUnregisterContactFrameCallback", required: true,
                                                as: RegisterCallbackFn.self)
        deviceStart = lookup("MTDeviceStart", required: true, as: StartFn.self)
        deviceStop = lookup("MTDeviceStop", required: true, as: StopFn.self)
        createDefault = lookup("MTDeviceCreateDefault", required: false, as: CreateDefaultFn.self)
        deviceRelease = lookup("MTDeviceRelease", required: false, as: ReleaseFn.self)
        deviceIsRunning = lookup("MTDeviceIsRunning", required: false, as: BoolQueryFn.self)
        deviceIsBuiltIn = lookup("MTDeviceIsBuiltIn", required: false, as: BoolQueryFn.self)
        deviceGetFamilyID = lookup("MTDeviceGetFamilyID", required: false, as: Int32QueryFn.self)
        deviceGetDeviceID = lookup("MTDeviceGetDeviceID", required: false, as: UInt64QueryFn.self)
        deviceGetSensorSurfaceDimensions = lookup("MTDeviceGetSensorSurfaceDimensions", required: false,
                                                  as: DimensionsFn.self)
        symbols = statuses
    }

    /// Name → required. Must list the same symbols the initializer resolves.
    private static let symbolTable: [(String, Bool)] = [
        ("MTDeviceCreateList", true),
        ("MTRegisterContactFrameCallback", true),
        ("MTUnregisterContactFrameCallback", true),
        ("MTDeviceStart", true),
        ("MTDeviceStop", true),
        ("MTDeviceCreateDefault", false),
        ("MTDeviceRelease", false),
        ("MTDeviceIsRunning", false),
        ("MTDeviceIsBuiltIn", false),
        ("MTDeviceGetFamilyID", false),
        ("MTDeviceGetDeviceID", false),
        ("MTDeviceGetSensorSurfaceDimensions", false),
    ]

    /// Nil when streaming is possible, otherwise why not.
    var unavailableReason: String? {
        if !isLoaded {
            return "MultitouchSupport.framework could not be loaded (\(loadError ?? "unknown error"))"
        }
        let missing: [String] = symbols.filter { $0.isRequired && !$0.isResolved }.map { $0.name }
        if !missing.isEmpty {
            return "MultitouchSupport.framework is missing required symbols: " + missing.joined(separator: ", ")
        }
        if deviceIsBuiltIn == nil && deviceGetFamilyID == nil && deviceGetSensorSurfaceDimensions == nil {
            return "MultitouchSupport.framework offers no way to tell a Magic Mouse from a trackpad on this macOS version"
        }
        if let problem = MTTouchLayout.validate() { return "Touch data layout check failed: \(problem)" }
        return nil
    }

    /// Calls `MTDeviceCreateList`. The returned array owns (retains) the device objects, so the
    /// device pointers stay valid exactly as long as the array is kept alive.
    func copyDeviceList() -> MultitouchDeviceList? {
        guard let createList = createList, let raw = createList() else { return nil }
        let array: CFArray = Unmanaged<CFArray>.fromOpaque(raw).takeRetainedValue()
        var refs: [MTDeviceRef] = []
        let count: Int = CFArrayGetCount(array)
        var index = 0
        while index < count {
            if let value = CFArrayGetValueAtIndex(array, index) {
                refs.append(UnsafeMutableRawPointer(mutating: value))
            }
            index += 1
        }
        return MultitouchDeviceList(owner: array, refs: refs)
    }

    /// Reads the static properties of a device. Does not start it.
    func describe(_ device: MTDeviceRef, index: Int) -> MultitouchDeviceDescription {
        var description = MultitouchDeviceDescription(index: index)
        if let isBuiltIn = deviceIsBuiltIn { description.isBuiltIn = isBuiltIn(device) }
        if let isRunning = deviceIsRunning { description.isRunning = isRunning(device) }
        if let getFamilyID = deviceGetFamilyID {
            var family: Int32 = 0
            if getFamilyID(device, &family) == 0 { description.familyID = Int(family) }
        }
        if let getDeviceID = deviceGetDeviceID {
            var identifier: UInt64 = 0
            if getDeviceID(device, &identifier) == 0 { description.deviceID = identifier }
        }
        if let getDimensions = deviceGetSensorSurfaceDimensions {
            var width: Int32 = 0
            var height: Int32 = 0
            if getDimensions(device, &width, &height) == 0, width > 0, height > 0 {
                description.surfaceWidthMM = Double(width) / 100
                description.surfaceHeightMM = Double(height) / 100
            }
        }
        let verdict = MultitouchDeviceClassifier.classify(isBuiltIn: description.isBuiltIn,
                                                          familyID: description.familyID,
                                                          widthMM: description.surfaceWidthMM,
                                                          heightMM: description.surfaceHeightMM)
        description.deviceClass = verdict.deviceClass
        description.classificationReason = verdict.reason
        return description
    }
}

/// Keeps the CFArray returned by `MTDeviceCreateList` (and therefore the devices) alive.
final class MultitouchDeviceList {
    let owner: CFArray
    let refs: [MTDeviceRef]
    init(owner: CFArray, refs: [MTDeviceRef]) {
        self.owner = owner
        self.refs = refs
    }
}
