import SwiftUI
import AppKit
import Domain
import SystemBridge

// MARK: - SettingsView (T169, US8)
//
// Per tasks.md T169 and spec FR-130/FR-131/FR-132/FR-133/FR-134: Dock icon
// toggle, sync status entry, permissions (on-demand only — FR-133). Global
// shortcuts were removed 2026-08-10 (user decision — no global hotkeys; the
// Settings "General" panel holds only the Dock toggle).

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("local.stickynotes.showDockIcon") private var showDockIcon = true
    /// The sync composition root (T285) — drives the Sync tab.
    private let syncCoordinator: SyncCoordinator?
    @State private var selectedTab: SettingsTab = .general
    /// Live permission statuses (refreshed on appear and on app activation —
    /// the user may change them in System Settings and come back).
    @State private var screenRecordingStatus: PermissionStatus = .notDetermined
    @State private var accessibilityPermissionStatus: PermissionStatus = .notDetermined
    /// Visible feedback for the last accessibility-request outcome (the
    /// system prompt may be suppressed on some configurations — e.g.
    /// ad-hoc-signed builds — so the user must see what happened).
    @State private var accessibilityRequestResult: String?

    /// Navigation between the settings sections. A segmented control (not a
    /// `TabView`) is used so the window stays a plain macOS settings window:
    /// `TabView` renders its tabs as title-bar toolbar icons in accessory
    /// windows on macOS 26, which conflicts with the native settings look.
    public enum SettingsTab: String, CaseIterable, Identifiable {
        case general
        case sync
        case fonts
        case permissions

        public var id: String { rawValue }

        var label: String {
            switch self {
            case .general: return String(localized: "General")
            case .sync: return String(localized: "Sync")
            case .fonts: return String(localized: "Fonts")
            case .permissions: return String(localized: "Permissions")
            }
        }
    }

    public init(syncCoordinator: SyncCoordinator? = nil) {
        self.syncCoordinator = syncCoordinator
    }

    public var body: some View {
        // 003 T044 (FR-050): native toolbar-style tab navigation (macOS
        // 14+ TabView) replaces the segmented control — System Settings
        // style. The four panels fit their content (FR-051).
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            SyncSettingsView(syncCoordinator: syncCoordinator)
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                .tag(SettingsTab.sync)
            FontPreferenceView()
                .tabItem { Label("Fonts", systemImage: "textformat") }
                .tag(SettingsTab.fonts)
            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock") }
                .tag(SettingsTab.permissions)
        }
        .frame(minWidth: 480, idealWidth: 520)
    }

    private var generalTab: some View {
        Form {
            // FR-134: Dock icon toggle via activation policy.
            Toggle("Show icon in Dock", isOn: $showDockIcon)
                .onChange(of: showDockIcon) { _, newValue in
                    try? DockActivationBridge.setDockEnabled(newValue)
                }
        }
        // Grouped form style: native macOS settings card groups (consistent
        // with the Sync tab).
        .formStyle(.grouped)
        .padding(20)
    }

    private var permissionsTab: some View {
        Form {
            Section {
                LabeledContent("Screen recording") {
                    HStack(spacing: 8) {
                        statusLabel(screenRecordingStatus)
                        permissionActionButtons(for: .screenRecording)
                    }
                }
                // 003 T048 (FR-056): why it's needed + the dependent
                // feature, in the user's own terms.
                LabeledContent("Used for") {
                    Text("Capturing screen regions and windows into new notes")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Accessibility") {
                    HStack(spacing: 8) {
                        statusLabel(accessibilityPermissionStatus)
                        permissionActionButtons(for: .accessibility)
                    }
                }
                LabeledContent("Used for") {
                    Text("Advanced note actions (not currently required — optional)")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                if let accessibilityRequestResult {
                    Label(accessibilityRequestResult, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Permissions are requested only when you use the related feature (FR-131).")
            } footer: {
                // Constitution VI / FR-056: unused permissions are
                // optional, never presented as mandatory.
                Text("Optional: you can use Sticky Notes fully without granting either permission.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear(perform: refreshPermissionStatuses)
        // The user may toggle permissions in System Settings and return —
        // refresh on every app activation.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatuses()
        }
    }

    /// Action buttons per permission state: an in-place "Allow…" request for
    /// screen recording (the system dialog appears right here), with the
    /// System Settings fallback for the denied state. Accessibility is never
    /// proactively requested — the current product has no feature needing it
    /// (FR-131: accessibility permission MUST NOT be requested merely because
    /// a future feature might use it) — so only the status + pane link show.
    @ViewBuilder
    private func permissionActionButtons(for domain: PermissionDomain) -> some View {
        switch domain {
        case .screenRecording:
            if screenRecordingStatus == .granted {
                EmptyView()
            } else {
                Button("Allow Screen Recording…") {
                    // Presents the system authorization dialog (or routes to
                    // the Screen Capture pane when previously denied). On
                    // ad-hoc-signed builds / macOS 27 beta the system prompt
                    // may not appear — fall back to opening the pane.
                    let granted = PermissionService.requestScreenRecording()
                    refreshPermissionStatuses()
                    if !granted {
                        _ = PermissionService.openSystemSettings(for: .screenRecording)
                    }
                }
                .controlSize(.small)
                if screenRecordingStatus == .denied {
                    Button("Open System Settings") {
                        _ = PermissionService.openSystemSettings(for: .screenRecording)
                    }
                    .controlSize(.small)
                }
            }
        case .accessibility:
            if accessibilityPermissionStatus != .granted {
                // Constitution 2.0.0 / FR-131 (2026-08-08): an explicit,
                // user-initiated request from the Settings page is allowed —
                // never automatic, never at startup.
                Button("Allow Accessibility…") {
                    let granted = PermissionService.requestAccessibility()
                    refreshPermissionStatuses()
                    if granted {
                        accessibilityRequestResult = String(localized: "Accessibility granted.")
                    } else {
                        // The system prompt is suppressed for ad-hoc-signed
                        // builds / macOS 27 beta — open the Accessibility
                        // pane directly so the user can enable the app.
                        _ = PermissionService.openSystemSettings(for: .accessibility)
                        accessibilityRequestResult = String(localized: "Accessibility not granted yet. If no dialog appeared, enable it in System Settings > Privacy & Security > Accessibility.")
                    }
                }
                .controlSize(.small)
                if accessibilityPermissionStatus == .denied {
                    Button("Open System Settings") {
                        _ = PermissionService.openSystemSettings(for: .accessibility)
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    /// The live permission status indicator (never color-only — FR-044):
    /// icon + text for granted / denied / not-yet-asked.
    @ViewBuilder
    private func statusLabel(_ status: PermissionStatus) -> some View {
        switch status {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            Label("Denied", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .notDetermined:
            Label("Not determined", systemImage: "circle")
                .foregroundStyle(.secondary)
        }
    }

    private func refreshPermissionStatuses() {
        screenRecordingStatus = PermissionService.screenRecordingStatus()
        accessibilityPermissionStatus = PermissionService.accessibilityStatus()
    }
}

extension Notification.Name {
    /// 003 T032 (SC-004): Edit/Insert menu block-insertion requests,
    /// dispatched to the key note window's host by the coordinator.
    static let stickyRequestInsertTodo = Notification.Name("sticky.requestInsertTodo")
    static let stickyRequestInsertCode = Notification.Name("sticky.requestInsertCode")
    static let stickyRequestInsertFileReference = Notification.Name("sticky.requestInsertFileReference")
    static let stickyRequestCaptureScreenshot = Notification.Name("sticky.requestCaptureScreenshot")
}
