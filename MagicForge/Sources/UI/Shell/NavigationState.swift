import SwiftUI
import Observation
import MFCore

/// Every destination in the main window's sidebar. Raw values are stable identifiers.
public enum SidebarSection: String, CaseIterable, Identifiable, Sendable {
    case dashboard, gestures, gestureStudio, touchLab
    case profiles, actions, automation, radialMenu, scrolling, ai
    case devices, permissions, settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .gestures: return "Gestures"
        case .gestureStudio: return "Gesture Studio"
        case .touchLab: return "Touch Lab"
        case .profiles: return "Profiles"
        case .actions: return "Actions"
        case .automation: return "Automation Builder"
        case .radialMenu: return "Radial Menu"
        case .scrolling: return "Scrolling"
        case .ai: return "AI Integrations"
        case .devices: return "Devices"
        case .permissions: return "Permissions"
        case .settings: return "Settings"
        }
    }

    /// SF Symbol name.
    public var symbolName: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .gestures: return "hand.tap"
        case .gestureStudio: return "wand.and.stars"
        case .touchLab: return "hand.point.up.left"
        case .profiles: return "square.stack.3d.up"
        case .actions: return "bolt"
        case .automation: return "arrow.triangle.branch"
        case .radialMenu: return "circle.grid.cross"
        case .scrolling: return "arrow.up.and.down"
        case .ai: return "sparkles"
        case .devices: return "magicmouse"
        case .permissions: return "lock.shield"
        case .settings: return "gearshape"
        }
    }
}

/// Shared navigation state of the main window, injected with `.environment(_:)`.
@MainActor
@Observable
public final class NavigationState {
    public var section: SidebarSection = .dashboard
    /// Profile whose bindings the gesture screens edit; nil = global profile.
    public var editingProfileID: UUID?
    public var selectedGesture: GestureKind?

    public init() {}
}

/// Identifier of the main `Window` scene (used with `openWindow(id:)`).
public enum MagicForgeWindowID {
    public static let main = "main"
}

private struct MFConfigurationLocationKey: EnvironmentKey {
    static let defaultValue: URL? = nil
}

public extension EnvironmentValues {
    /// Where the configuration file lives, when the store is file based. Set by the composition
    /// root (the model does not expose the store); nil hides "Reveal in Finder".
    var mfConfigurationLocation: URL? {
        get { self[MFConfigurationLocationKey.self] }
        set { self[MFConfigurationLocationKey.self] = newValue }
    }
}
