import Foundation
import MFCore
import MFUtilities
import MFProfiles

extension AppModel {
    /// JSON diagnostics (versions, adapter, capabilities, metrics, permissions, recent gesture
    /// kinds). Touch coordinates are included only when `includeTouchFrames` is true, and then
    /// only what the Touch Lab currently shows (`touchFeed.snapshot()`); nothing is recorded in
    /// the background. Device names, identifiers, bundle identifiers, script text and file paths
    /// are never included.
    public func diagnosticsReport(includeTouchFrames: Bool) -> Data {
        syncPipelineMetrics()
        let info = Bundle.main.infoDictionary
        let process = ProcessInfo.processInfo
        var report: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "app": [
                "name": "MagicForge",
                "version": (info?["CFBundleShortVersionString"] as? String) ?? "development",
                "build": (info?["CFBundleVersion"] as? String) ?? "development",
                "configurationSchema": configuration.schemaVersion,
            ] as [String: Any],
            "system": [
                "operatingSystem": process.operatingSystemVersionString,
                "processorCount": process.activeProcessorCount,
                "physicalMemoryMB": Int(process.physicalMemory / 1_048_576),
            ] as [String: Any],
            "engine": [
                "isRunning": isRunning,
                "isPaused": isPaused,
                "actionsSuppressed": suppressActions,
                "syntheticInputActive": isSyntheticInputActive,
                "runningWorkflows": runningWorkflows.count,
                "persistenceProblem": persistenceError != nil,
                "profileSource": resolvedProfile.source.rawValue,
                "profileOverrideActive": profileOverrideID != nil,
            ] as [String: Any],
            "adapter": adapterReport(),
            "capabilities": [
                "rawContacts": adapterStatus.capabilities.rawContacts,
                "maxContacts": adapterStatus.capabilities.maxContacts,
                "contactSize": adapterStatus.capabilities.contactSize,
                "pointerEvents": adapterStatus.capabilities.pointerEvents,
            ] as [String: Any],
            "devices": devices.map { device -> [String: Any] in
                var entry: [String: Any] = [
                    "model": device.model.rawValue,
                    "transport": device.transport,
                    "vendorID": device.vendorID,
                    "productID": device.productID,
                    "isConnected": device.isConnected,
                    "surfaceWidthMM": device.surface.widthMM,
                    "surfaceHeightMM": device.surface.heightMM,
                ]
                if let battery = device.batteryPercent { entry["batteryPercent"] = battery }
                return entry
            },
            "metrics": [
                "framesProcessed": metrics.framesProcessed,
                "gesturesRecognized": metrics.gesturesRecognized,
                "actionsExecuted": metrics.actionsExecuted,
                "actionFailures": metrics.actionFailures,
                "averageProcessingTime": metrics.averageProcessingTime,
                "maxProcessingTime": metrics.maxProcessingTime,
                "averageDeliveryLatency": metrics.averageDeliveryLatency,
                "averageDispatchLatency": metrics.averageDispatchLatency,
            ] as [String: Any],
            "counts": [
                "profiles": configuration.profiles.count,
                "enabledBindings": effectiveBindings.count,
                "unavailableBindings": resolvedProfile.unavailableBindings.count,
                "workflows": configuration.workflows.count,
                "radialMenus": configuration.radialMenus.count,
                "aiTemplates": configuration.ai.templates.count,
                "approvedScripts": configuration.approvedScriptHashes.count,
                "untrustedScripts": untrustedScripts().count,
                "activityEntries": activityLog.count,
                "activityErrors": activityLog.filter { $0.level == .error }.count,
            ] as [String: Any],
            "recentGestureKinds": recentGestures.map { $0.event.kind.rawValue },
        ]
        var permissionReport: [String: String] = [:]
        for (kind, status) in permissions { permissionReport[kind.rawValue] = status.rawValue }
        report["permissions"] = permissionReport
        report["touchFramesIncluded"] = includeTouchFrames
        if includeTouchFrames { report["touch"] = touchReport() }

        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        return (try? JSONSerialization.data(withJSONObject: report, options: options)) ?? Data("{}".utf8)
    }

    private func adapterReport() -> [String: Any] {
        var entry: [String: Any] = [
            "identifier": adapterStatus.identifier,
            "displayName": adapterStatus.displayName,
            "usesPrivateAPI": adapterStatus.usesPrivateAPI,
        ]
        switch adapterStatus.state {
        case .stopped: entry["state"] = "stopped"
        case .running: entry["state"] = "running"
        case .unavailable(let reason):
            entry["state"] = "unavailable"
            entry["reason"] = reason
        }
        return entry
    }

    private func touchReport() -> [String: Any] {
        let snapshot = touchFeed.snapshot()
        var entry: [String: Any] = [
            "isSynthetic": snapshot.isSynthetic,
            "totalFrames": snapshot.totalFrames,
            "framesPerSecond": snapshot.framesPerSecond,
            "phase": snapshot.live.phase,
        ]
        if let frame = snapshot.latest {
            entry["latestFrame"] = [
                "timestamp": frame.timestamp,
                "contacts": frame.contacts.map { contact -> [String: Any] in
                    ["id": contact.id, "x": contact.x, "y": contact.y, "size": contact.size, "phase": contact.phase.rawValue]
                },
            ] as [String: Any]
        }
        var trails: [String: Any] = [:]
        for (id, points) in snapshot.trails {
            trails[String(id)] = points.map { ["x": $0.x, "y": $0.y, "timestamp": $0.timestamp] }
        }
        entry["trails"] = trails
        return entry
    }
}
