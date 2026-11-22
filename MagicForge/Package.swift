// swift-tools-version:5.9
import PackageDescription
import Foundation

// MagicForge package layout
// -------------------------
// Portable modules (build + test on macOS AND Linux): MFUtilities, MFCore, MFGestures,
// MFProfiles, MFAutomation, MFIntegrations, MFEngine.
// macOS-only modules: MFDevices, MFInput, MFActions, MFUI, the MagicForge app and mfprobe.
//
// MF_ONLY=<ModuleName> restricts the graph to MFUtilities + MFCore + that one module and its
// test target, so one module can be built/tested while others are mid-edit:
//   MF_ONLY=MFGestures swift test --scratch-path .build-gestures

let only = ProcessInfo.processInfo.environment["MF_ONLY"]

var products: [Product] = []
var targets: [Target] = [
    .target(name: "MFUtilities", path: "Sources/Utilities"),
    .target(name: "MFCore", dependencies: ["MFUtilities"], path: "Sources/Core"),
]

struct Module {
    let name: String, path: String, deps: [String], tests: String?
}

let portable: [Module] = [
    Module(name: "MFGestures", path: "Sources/Gestures", deps: [], tests: "GestureTests"),
    Module(name: "MFProfiles", path: "Sources/Profiles", deps: [], tests: "ProfileTests"),
    Module(name: "MFAutomation", path: "Sources/Automation", deps: [], tests: "AutomationTests"),
    Module(name: "MFIntegrations", path: "Sources/Integrations", deps: [], tests: "IntegrationTests"),
    Module(name: "MFEngine", path: "Sources/Engine",
           deps: ["MFGestures", "MFProfiles", "MFAutomation", "MFIntegrations"], tests: "EngineTests"),
]

for module in portable where only == nil || only == module.name {
    // With MF_ONLY the dependencies on sibling modules are still required for MFEngine.
    let deps: [Target.Dependency] = ["MFCore", "MFUtilities"] + module.deps.map { Target.Dependency(stringLiteral: $0) }
    targets.append(.target(name: module.name, dependencies: deps, path: module.path))
    if let tests = module.tests {
        targets.append(.testTarget(name: tests, dependencies: [Target.Dependency(stringLiteral: module.name), "MFCore"],
                                   path: "Tests/\(tests)"))
    }
}
if only == "MFEngine" {
    for module in portable where ["MFGestures", "MFProfiles", "MFAutomation", "MFIntegrations"].contains(module.name) {
        targets.append(.target(name: module.name, dependencies: ["MFCore", "MFUtilities"], path: module.path))
    }
}
if only == nil || only == "MFCore" {
    targets.append(.testTarget(name: "ActionTests", dependencies: ["MFCore"], path: "Tests/ActionTests"))
}

#if os(macOS)
if only == nil {
    targets += [
        .target(name: "MFDevices", dependencies: ["MFCore", "MFUtilities"], path: "Sources/Devices"),
        .target(name: "MFInput", dependencies: ["MFCore", "MFUtilities"], path: "Sources/Input"),
        .target(name: "MFActions", dependencies: ["MFCore", "MFUtilities"], path: "Sources/Actions"),
        .target(name: "MFUI", dependencies: ["MFCore", "MFUtilities", "MFEngine", "MFGestures", "MFProfiles"],
                path: "Sources/UI"),
        .executableTarget(name: "MagicForge",
                          dependencies: ["MFCore", "MFUtilities", "MFEngine", "MFGestures", "MFProfiles", "MFAutomation",
                                         "MFIntegrations", "MFDevices", "MFInput", "MFActions", "MFUI"],
                          path: "Sources/App"),
        .executableTarget(name: "mfprobe", dependencies: ["MFCore", "MFUtilities", "MFDevices", "MFInput", "MFGestures"],
                          path: "Sources/Probe"),
    ]
    products += [
        .executable(name: "MagicForge", targets: ["MagicForge"]),
        .executable(name: "mfprobe", targets: ["mfprobe"]),
    ]
}
#endif

let package = Package(
    name: "MagicForge",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
