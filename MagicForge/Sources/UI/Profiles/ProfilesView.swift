import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MFCore
import MFEngine
import MFUtilities

/// An import that has been parsed and is waiting for the user's decision.
struct ProfilesPendingImport: Identifiable {
    let id = UUID()
    let preview: ImportPreview
}

/// Master–detail profile management, import / export and backup.
@MainActor
public struct ProfilesView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationState.self) private var navigation

    @State private var selectedID: UUID?
    @State private var isAddingProfile: Bool = false
    @State private var deleteCandidateID: UUID?
    @State private var pendingImport: ProfilesPendingImport?
    @State private var errorMessage: String?

    private let log = Log("ui.profiles")

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MFPageHeader("Profiles", subtitle: "Different gestures for different apps. The global profile applies everywhere else.",
                         toolbar: { toolbarMenu })
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
            Divider()
            HStack(spacing: 0) {
                ProfilesListPane(
                    selection: selectionBinding,
                    onAdd: { isAddingProfile = true },
                    onDuplicate: duplicateSelected,
                    onDelete: { deleteCandidateID = resolvedSelection }
                )
                .frame(width: 250)
                Divider()
                ProfilesDetailPane(profileID: resolvedSelection)
                    .id(resolvedSelection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isAddingProfile) {
            ProfilesAddSheet(onCreate: createProfile)
        }
        .sheet(item: $pendingImport) { pending in
            ProfilesImportSheet(preview: pending.preview, onApply: { approveScripts in
                model.applyImport(pending.preview, approveScripts: approveScripts)
            })
        }
        .confirmationDialog(deleteTitle, isPresented: deleteDialogBinding, titleVisibility: .visible, actions: {
            Button("Delete Profile", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) {}
        }, message: {
            Text("Its gesture bindings are removed. This cannot be undone.")
        })
        .shellErrorAlert("Profiles", message: $errorMessage)
    }

    // MARK: Selection

    /// Falls back to the profile being edited in the gesture screens, then to the global profile.
    private var resolvedSelection: UUID {
        let profiles: [Profile] = model.configuration.profiles
        if let selectedID, profiles.contains(where: { $0.id == selectedID }) { return selectedID }
        if let editing = navigation.editingProfileID, profiles.contains(where: { $0.id == editing }) { return editing }
        return model.configuration.globalProfileID
    }

    private var selectionBinding: Binding<UUID?> {
        let current: UUID = resolvedSelection
        return Binding<UUID?>(
            get: { current },
            set: { newValue in
                if let newValue { selectedID = newValue }
            }
        )
    }

    // MARK: Toolbar

    private var toolbarMenu: some View {
        Menu {
            Button("Import Profiles…") { importFile(title: "Import Profiles") }
            Button("Export Selected Profile…") { exportProfiles([resolvedSelection], suggestedName: "MagicForge Profile.json") }
            Button("Export All Profiles…") {
                exportProfiles(model.configuration.profiles.map(\.id), suggestedName: "MagicForge Profiles.json")
            }
            Divider()
            Button("Back Up Everything…") { exportBackup() }
            Button("Restore from Backup…") { importFile(title: "Restore from Backup") }
        } label: {
            Label("Import & Export", systemImage: "square.and.arrow.up.on.square")
        }
        .fixedSize()
    }

    // MARK: Actions

    private func createProfile(name: String, bundleIdentifiers: [String]) {
        let profile: Profile = model.addProfile(name: name, bundleIdentifiers: bundleIdentifiers)
        selectedID = profile.id
    }

    private func duplicateSelected() {
        if let copy = model.duplicateProfile(resolvedSelection) {
            selectedID = copy.id
        } else {
            errorMessage = "The profile could not be duplicated."
        }
    }

    private var deleteTitle: String {
        let name: String = model.configuration.profiles.first { $0.id == deleteCandidateID }?.name ?? "profile"
        return "Delete “\(name)”?"
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding<Bool>(
            get: { deleteCandidateID != nil },
            set: { presented in
                if !presented { deleteCandidateID = nil }
            }
        )
    }

    private func confirmDelete() {
        guard let id = deleteCandidateID else { return }
        deleteCandidateID = nil
        guard id != model.configuration.globalProfileID else { return }
        if navigation.editingProfileID == id { navigation.editingProfileID = nil }
        model.deleteProfile(id)
        selectedID = nil
    }

    private func importFile(title: String) {
        guard let url = ShellFilePanels.openFile(title: title, types: [UTType.json]) else { return }
        do {
            let data: Data = try Data(contentsOf: url)
            let preview: ImportPreview = try model.previewImport(data)
            pendingImport = ProfilesPendingImport(preview: preview)
        } catch {
            log.error("Import failed: \(ShellErrorText.describe(error))")
            errorMessage = ShellErrorText.describe(error)
        }
    }

    private func exportProfiles(_ ids: [UUID], suggestedName: String) {
        do {
            let data: Data = try model.exportProfiles(ids)
            _ = try ShellFilePanels.saveJSON(data, suggestedName: suggestedName, title: "Export Profiles")
        } catch {
            log.error("Export failed: \(ShellErrorText.describe(error))")
            errorMessage = ShellErrorText.describe(error)
        }
    }

    private func exportBackup() {
        do {
            let data: Data = try model.exportBackup()
            _ = try ShellFilePanels.saveJSON(data, suggestedName: "MagicForge Backup.json", title: "Back Up MagicForge")
        } catch {
            log.error("Backup failed: \(ShellErrorText.describe(error))")
            errorMessage = ShellErrorText.describe(error)
        }
    }
}
