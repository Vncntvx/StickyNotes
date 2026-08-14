import SwiftUI
import AppKit
import Domain
import SystemBridge

// MARK: - SettingsView (T169, US8; Rev 2 2026-08-14, FR-050/FR-051/FR-056)
//
// Per tasks.md T169 and spec FR-130/FR-131/FR-132/FR-133/FR-134: Dock icon
// toggle, sync status entry, permissions (on-demand only — FR-133). Global
// shortcuts were removed 2026-08-10 (user decision — no global hotkeys; the
// Settings "General" panel holds only the Dock toggle).
//
// Rev 2 (2026-08-14): three logical areas (General/Sync/Privacy — FR-050);
// Fonts folded into General's Notes section (FR-055); Permissions renamed
// Privacy (FR-056). The root frame carries the STABLE shell geometry
// (SettingsWindowPolicy) so tab switches never resize the window (FR-051).

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("local.stickynotes.showDockIcon") private var showDockIcon = true
    /// The sync composition root (T285) — drives the Sync tab.
    private let syncCoordinator: SyncCoordinator?
    /// Phase 5: the global typography preference source (single bootstrap
    /// instance) — drives the Notes section.
    private let typography: TypographyPreferences
    @State private var selectedTab: SettingsTab = .general
    /// Live screen-recording status (refreshed on appear and on app
    /// activation — the user may change it in System Settings and come
    /// back). Rev 2: only the two states the public API can observe are
    /// surfaced (granted vs not granted — FR-056).
    @State private var screenRecordingStatus: PermissionStatus = .notDetermined

    /// Navigation between the settings sections: native macOS toolbar-style
    /// tabs (TabView, FR-050). Three logical areas (Rev 2): General / Sync /
    /// Privacy. Fonts folded into General's Notes section.
    public enum SettingsTab: String, CaseIterable, Identifiable {
        case general
        case sync
        case privacy

        public var id: String { rawValue }

        var label: String {
            switch self {
            case .general: return String(localized: "General")
            case .sync: return String(localized: "Sync")
            case .privacy: return String(localized: "Privacy")
            }
        }
    }

    public init(syncCoordinator: SyncCoordinator? = nil, typography: TypographyPreferences = TypographyPreferences()) {
        self.syncCoordinator = syncCoordinator
        self.typography = typography
    }

    public var body: some View {
        // 003 T044 (FR-050): native toolbar-style tab navigation (macOS
        // 14+ TabView) replaces the segmented control — System Settings
        // style. Rev 2: three logical areas (FR-050).
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            SyncSettingsView(syncCoordinator: syncCoordinator)
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                .tag(SettingsTab.sync)
            privacyTab
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
                .tag(SettingsTab.privacy)
        }
        // Rev 2 (FR-051): the stable window shell. Geometry comes from THIS
        // frame (values in SettingsWindowPolicy — implementation policy),
        // never from per-tab content intrinsic size.
        .frame(
            minWidth: SettingsWindowPolicy.minimumWidth,
            idealWidth: SettingsWindowPolicy.defaultWidth,
            minHeight: SettingsWindowPolicy.minimumHeight,
            idealHeight: SettingsWindowPolicy.defaultHeight
        )
    }

    private var generalTab: some View {
        Form {
            // FR-134: Dock icon toggle via activation policy.
            Section("App") {
                Toggle("Show icon in Dock", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { _, newValue in
                        try? DockActivationBridge.setDockEnabled(newValue)
                    }
            }
            // Rev 2 (FR-055): the note-font preference lives in General's
            // Notes section (was its own first-level tab). Phase 5: the
            // section also carries the global text-spacing presets.
            Section {
                NoteFontSection(typography: typography)
            } header: {
                Text("Notes")
            } footer: {
                // Polish round 2: concise — the first sentence was already
                // carried by the section semantics.
                Text("Applies to all notes. Chinese text uses a matching system font when needed.")
                    .font(.caption)
            }
        }
        // Grouped form style: native macOS settings card groups (consistent
        // with the Sync tab).
        .formStyle(.grouped)
        .padding(20)
    }

    private var privacyTab: some View {
        Form {
            // Polish round 2: the footer duplicated the row description
            // (what / why / state / next step are all already present) —
            // removed rather than reworded.
            Section {
                screenRecordingRow
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear(perform: refreshPermissionStatus)
        // The user may toggle permissions in System Settings and return —
        // refresh on every app activation.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatus()
        }
    }

    /// Rev 2 (FR-056): one complete row — what the permission is for on the
    /// left, the observable status + action on the right. The UI only
    /// exposes the granted / not-granted distinction the public API can
    /// reliably observe (`CGPreflightScreenCaptureAccess`); it never
    /// pretends to distinguish not-determined from denied.
    private var screenRecordingRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Recording")
                Text("Capture a screen region or window and add it to a note.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if screenRecordingStatus == .granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Not Granted")
                    .foregroundStyle(.secondary)
                Button("Enable…") {
                    // Presents the system authorization dialog when possible;
                    // when the request does not grant access (previously
                    // denied, or the prompt was suppressed), route to the
                    // Screen Capture pane.
                    let granted = PermissionService.requestScreenRecording()
                    refreshPermissionStatus()
                    if !granted {
                        _ = PermissionService.openSystemSettings(for: .screenRecording)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func refreshPermissionStatus() {
        screenRecordingStatus = PermissionService.screenRecordingStatus()
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
