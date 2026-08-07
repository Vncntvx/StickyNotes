import SwiftUI
import Domain

// MARK: - SyncStatusView (T170/T209/T272)
//
// Per tasks.md T170/T209/T272 and spec FR-014a/FR-150/FR-152/FR-165/FR-141b:
// a non-blocking sync-status area in the menu-bar library. When NO
// VaultConfiguration exists the status shows "not configured" (never an
// error — FR-014a); error/status states appear only when sync is actually
// configured. Diagnostics are sanitized (credentials/unlocked secrets never
// in logs or exported diagnostics — FR-165). Background sync runs are
// SILENT (FR-141b); manual sync surfaces explicit non-blocking status.

/// The sync-status area. `configuration` mirrors the local
/// VaultConfiguration (or nil when sync is unconfigured).
public struct SyncStatusView: View {
    let isConfigured: Bool
    let lastSuccessfulSyncAt: Date?
    let lastErrorCode: String?
    let isInProgress: Bool
    let manualSync: () -> Void

    public init(
        isConfigured: Bool,
        lastSuccessfulSyncAt: Date? = nil,
        lastErrorCode: String? = nil,
        isInProgress: Bool = false,
        manualSync: @escaping () -> Void = {}
    ) {
        self.isConfigured = isConfigured
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastErrorCode = lastErrorCode
        self.isInProgress = isInProgress
        self.manualSync = manualSync
    }

    public var body: some View {
        HStack(spacing: 6) {
            if !isConfigured {
                // FR-014a: "not configured" — never an error.
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.secondary)
                Text("Sync not configured")
                    .foregroundStyle(.secondary)
            } else if isInProgress {
                // FR-141b: explicit non-blocking status for user-initiated
                // manual sync only.
                ProgressView()
                    .controlSize(.small)
                Text("Syncing…")
                    .foregroundStyle(.secondary)
            } else if lastErrorCode != nil {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("Sync issue")
                    .foregroundStyle(.secondary)
                Button("Retry", action: manualSync)
                    .controlSize(.small)
                    .accessibilityLabel("Retry synchronization")
            } else if let lastSuccessfulSyncAt {
                Image(systemName: "checkmark.icloud")
                    .foregroundStyle(.green)
                Text("Synced \(DisplayFormatters.relativeTime(lastSuccessfulSyncAt))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Sync ready")
                    .foregroundStyle(.secondary)
            }

            if isConfigured {
                Spacer()
                Button(action: manualSync) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Sync now")
                .accessibilityLabel("Sync now")
            }
        }
        .font(.caption)
    }
}
