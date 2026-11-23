import SwiftUI
import AppKit
import MFCore
import MFEngine

/// Root of the main window: grouped sidebar + detail for the selected section.
@MainActor
public struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    public init() {}

    public var body: some View {
        NavigationSplitView {
            ShellSidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ShellDetailContainer()
        }
        .frame(minWidth: 940, minHeight: 620)
        .sheet(isPresented: onboardingBinding) {
            ShellOnboardingView()
        }
    }

    /// The onboarding sheet is driven by configuration; it is only shown once the engine has
    /// loaded the saved configuration, so returning users never see it flash at launch.
    private var onboardingBinding: Binding<Bool> {
        let shouldShow: Bool = model.isRunning && !model.configuration.settings.hasCompletedOnboarding
        return Binding<Bool>(
            get: { shouldShow },
            set: { _ in }
        )
    }
}

/// Banners on top of the selected section's screen.
@MainActor
struct ShellDetailContainer: View {
    @Environment(NavigationState.self) private var navigation

    var body: some View {
        VStack(spacing: 0) {
            ShellBannerStack()
            ShellSectionDetail(section: navigation.section)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Maps every sidebar section to its screen.
@MainActor
struct ShellSectionDetail: View {
    let section: SidebarSection

    var body: some View {
        switch section {
        case .dashboard: DashboardView()
        case .gestures: GesturesView()
        case .gestureStudio: GestureStudioView()
        case .touchLab: TouchLabView()
        case .profiles: ProfilesView()
        case .actions: ActionsView()
        case .automation: AutomationBuilderView()
        case .radialMenu: RadialMenuView()
        case .scrolling: ScrollingView()
        case .ai: AIIntegrationsView()
        case .devices: DevicesView()
        case .permissions: PermissionsView()
        case .settings: SettingsView()
        }
    }
}
