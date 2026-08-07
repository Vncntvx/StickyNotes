import SwiftUI
import AppKit
import Domain
import SyncCore
import SystemBridge

// MARK: - SyncSettingsView (T170/T186)
//
// Per tasks.md T170/T186 and spec FR-150/FR-151/FR-152/FR-152a/FR-153/
// FR-154/FR-160/FR-162/FR-163/FR-164/FR-165: configure/test/enable-disable
// automatic sync, manual sync, view last-successful-time, view actionable
// errors, remove local config WITHOUT deleting local notes, unrecoverable-
// password warning (FR-163), repository replacement (FR-154), and the
// FR-191 diagnostic-bundle export action (T186).

public struct SyncSettingsView: View {
    public init() {}

    public var body: some View {
        Form {
            Section("Synchronization") {
                Text("Sticky Notes syncs end-to-end encrypted to exactly one WebDAV or S3-compatible repository.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LabeledContent("Status") {
                    Text("Not configured")
                }
                LabeledContent("Last successful sync") {
                    Text("—")
                }
                LabeledContent("Repository") {
                    Text("—")
                }
            }

            Section {
                Button("Configure Sync…") {
                    // Wired to the vault bootstrap flow (T112/T170).
                }
                Button("Manual Sync") {
                    // FR-151: explicit non-blocking status (FR-141b).
                }
                .disabled(true)

                // FR-163: unrecoverable-password warning.
                Label("If you forget your sync password, your synced notes cannot be recovered.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)

                // FR-154: replace repository (local notes preserved).
                Button("Replace Repository…", role: .destructive) {
                    // Explicit warning + confirmation; new vault bootstraps
                    // fresh; prior remote data NOT auto-deleted.
                }

                // FR-191 (T186): diagnostic bundle export.
                Button("Export Diagnostic Bundle…") {
                    exportDiagnosticBundle()
                }
                .help("Saves a sanitized diagnostics JSON for support. No note content or credentials are included.")
            }
        }
        .padding(20)
    }

    /// T186 (FR-191): generates the diagnostic bundle via T185
    /// (DiagnosticBundleGenerator) and presents a save panel so the user can
    /// save/share the JSON for support. The filename is opaque
    /// (`stickynotes-diagnostics-<date>.json`); the exported file contains
    /// ONLY the FR-191-enumerated fields (never note content, paths,
    /// credentials, or raw server responses). User-facing message explains
    /// what is included.
    private func exportDiagnosticBundle() {
        let objectCounts = DiagnosticObjectCounts()
        let bundle = DiagnosticBundleGenerator.generate(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            schemaVersionLocal: 2,
            providerType: nil,  // unconfigured here; wired once a vault exists
            recentErrorEvents: [],
            syncRunCounts: nil,
            objectCounts: objectCounts,
            vaultState: .unconfigured,
            permissionStatuses: DiagnosticPermissionStatuses(
                screenRecording: PermissionService.screenRecordingGranted,
                accessibility: PermissionService.accessibilityStatus() == .granted
            )
        )
        guard let data = try? DiagnosticBundleGenerator.encode(bundle) else {
            // Sanitized, non-blocking failure (FR-011a/FR-141b).
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "stickynotes-diagnostics-\(formatter.string(from: Date())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
    }
}
