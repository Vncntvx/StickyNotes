import SwiftUI
import AppKit
import Domain
import SystemBridge

// MARK: - SettingsView (T169, US8)
//
// Per tasks.md T169 and spec FR-130/FR-131/FR-132/FR-133/FR-134: global
// shortcuts config, Dock icon toggle, sync status entry, permissions
// (on-demand only — FR-133).

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("local.stickynotes.showDockIcon") private var showDockIcon = true
    @State private var clipboardNoteShortcut = "⌘⌥⇧N"
    /// The sync composition root (T285) — drives the Sync tab.
    private let syncCoordinator: SyncCoordinator?

    public init(syncCoordinator: SyncCoordinator? = nil) {
        self.syncCoordinator = syncCoordinator
    }

    public var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }

            SyncSettingsView(syncCoordinator: syncCoordinator)
                .tabItem { Label("Sync", systemImage: "icloud.and.arrow.up") }

            FontPreferenceView()
                .tabItem { Label("Fonts", systemImage: "textformat") }

            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 460, height: 340)
    }

    private var generalTab: some View {
        Form {
            // FR-134: Dock icon toggle via activation policy.
            Toggle("Show icon in Dock", isOn: $showDockIcon)
                .onChange(of: showDockIcon) { _, newValue in
                    try? DockActivationBridge.setDockEnabled(newValue)
                }

            // FR-131: global shortcut configuration.
            LabeledContent("New note from clipboard") {
                Text(clipboardNoteShortcut)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding(20)
    }

    private var permissionsTab: some View {
        Form {
            LabeledContent("Screen recording") {
                Button("Open System Settings") {
                    _ = PermissionService.openSystemSettings(for: .screenRecording)
                }
                .controlSize(.small)
            }
            LabeledContent("Accessibility") {
                Button("Open System Settings") {
                    _ = PermissionService.openSystemSettings(for: .accessibility)
                }
                .controlSize(.small)
            }
        }
        .padding(20)
    }
}
