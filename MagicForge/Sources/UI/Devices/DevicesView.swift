import SwiftUI
import MFCore
import MFEngine

/// Detected mice, the input adapter and an honest compatibility summary.
@MainActor
public struct DevicesView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    public init() {}

    public var body: some View {
        MFPage("Devices", subtitle: "Magic Mice this Mac has detected and how their touch data is read.", toolbar: {
            Button("Restart Input") {
                model.restartInput()
            }
            .help("Stop and restart the touch adapter and the event tap")
        }, content: {
            if model.devices.isEmpty {
                MFCard {
                    MFEmptyState(
                        systemImage: "magicmouse",
                        title: "No Magic Mouse detected",
                        message: "Connect a Magic Mouse with Bluetooth or its cable. Other mice and trackpads are not listed because MagicForge only works with the Magic Mouse touch surface."
                    )
                }
            } else {
                ForEach(model.devices) { device in
                    DevicesDeviceCard(device: device)
                }
            }
            DevicesAdapterCard()
            DevicesCompatibilityCard()
        })
    }
}

@MainActor
struct DevicesDeviceCard: View {
    let device: DeviceInfo

    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    var body: some View {
        MFCard {
            HStack {
                Image(systemName: device.isConnected ? "magicmouse.fill" : "magicmouse")
                    .font(.title2)
                    .foregroundStyle(device.isConnected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(device.name)
                    .font(.title3)
                    .fontWeight(.medium)
                Spacer()
                MFStatusBadge(device.isConnected ? "Connected" : "Disconnected",
                              style: device.isConnected ? .good : .neutral)
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 6) {
                    MFKeyValueRow("Model", value: device.model.displayName)
                    MFKeyValueRow("Connection", value: device.transport)
                    MFKeyValueRow("Battery", value: ShellFormat.battery(device.batteryPercent))
                    MFKeyValueRow("Touch surface", value: ShellFormat.surface(device.surface))
                }
                VStack(spacing: 6) {
                    MFKeyValueRow("Vendor ID", value: ShellFormat.hexID(device.vendorID))
                    MFKeyValueRow("Product ID", value: ShellFormat.hexID(device.productID))
                    MFKeyValueRow("Device identifier", value: device.id)
                }
            }
            Divider()
            calibrationRow
        }
    }

    private var calibrationRow: some View {
        let calibration: DeviceCalibration = model.calibration(forDevice: device.id)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Calibration")
                    .font(.callout)
                    .fontWeight(.medium)
                Text(calibrationSummary(calibration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Calibrate…") {
                navigation.section = .touchLab
            }
            .help("Open the Touch Lab to calibrate this mouse")
        }
    }

    private func calibrationSummary(_ calibration: DeviceCalibration) -> String {
        guard let date = calibration.calibratedAt else {
            return "Not calibrated. Default values are in use."
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let tapMS: String = String(format: "%.0f ms", calibration.typicalTapDuration * 1000)
        let swipe: String = String(format: "%.0f mm", calibration.typicalSwipeDistanceMM)
        return "Calibrated \(formatter.string(from: date)) · typical tap \(tapMS) · typical swipe \(swipe) · surface \(ShellFormat.surface(calibration.surface))"
    }
}

@MainActor
struct DevicesAdapterCard: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    var body: some View {
        let status: AdapterStatus = model.adapterStatus
        MFCard("Input adapter", systemImage: "dot.radiowaves.left.and.right") {
            HStack {
                Text(status.displayName)
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
                MFStatusBadge(status.state.shellLabel, style: status.state.shellStyle)
            }
            if let reason = status.state.shellUnavailableReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            MFKeyValueRow("Identifier", value: status.identifier)
            MFKeyValueRow("Uses private Apple API", value: ShellFormat.yesNo(status.usesPrivateAPI))
            MFKeyValueRow("Finger positions", value: ShellFormat.yesNo(status.capabilities.rawContacts))
            MFKeyValueRow("Simultaneous contacts", value: ShellFormat.count(status.capabilities.maxContacts))
            MFKeyValueRow("Contact size", value: ShellFormat.yesNo(status.capabilities.contactSize))
            MFKeyValueRow("Click and scroll events", value: ShellFormat.yesNo(status.capabilities.pointerEvents))
            HStack {
                Button("Restart Input") {
                    model.restartInput()
                }
                if !model.configuration.settings.allowPrivateMultitouch {
                    Button("Privacy Settings") {
                        navigation.section = .settings
                    }
                }
            }
        }
    }
}

/// States plainly which gestures depend on the private adapter and which do not.
@MainActor
struct DevicesCompatibilityCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let touchKinds: [GestureKind] = GestureKind.allCases.filter { $0.requirement == .rawContacts }
        let fallbackKinds: [GestureKind] = GestureKind.allCases.filter { $0.requirement == .pointerEvents }
        let availableTouch: Int = touchKinds.filter { $0.isAvailable(with: model.adapterStatus.capabilities) }.count
        let availableFallback: Int = fallbackKinds.filter { $0.isAvailable(with: model.adapterStatus.capabilities) }.count
        MFCard("Compatibility", systemImage: "checklist") {
            Text("macOS has no public API for finger positions on the Magic Mouse. The \(touchKinds.count) touch gestures (taps, swipes, pinch, rotate, zones and compound gestures) need Apple's private MultitouchSupport framework, which MagicForge loads at runtime. It is unsupported by Apple, may be missing or change in any macOS update, and can be turned off in Settings › Privacy.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("The \(fallbackKinds.count) fallback triggers (Control-Option with a click or scroll) use only the public event tap and need Accessibility permission.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            MFKeyValueRow("Touch gestures available now", value: "\(availableTouch) of \(touchKinds.count)")
            MFKeyValueRow("Fallback triggers available now", value: "\(availableFallback) of \(fallbackKinds.count)")
        }
    }
}
