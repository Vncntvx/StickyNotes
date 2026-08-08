import SwiftUI
import AppKit
import Carbon
import Domain
import SystemBridge

// MARK: - SettingsView (T169/T296, US8)
//
// Per tasks.md T169/T296 and spec FR-130/FR-131/FR-132/FR-133/FR-134/FR-120/
// FR-121: global shortcuts configuration (per-shortcut recorder, FR-120;
// conflict registration failures surface non-blockingly, FR-121), Dock icon
// toggle, sync status entry, permissions (on-demand only — FR-133).

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
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            Group {
                switch selectedTab {
                case .general:
                    generalTab
                case .sync:
                    SyncSettingsView(syncCoordinator: syncCoordinator)
                case .fonts:
                    FontPreferenceView()
                case .permissions:
                    permissionsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 460)
    }

    private var generalTab: some View {
        Form {
            // FR-134: Dock icon toggle via activation policy.
            Toggle("Show icon in Dock", isOn: $showDockIcon)
                .onChange(of: showDockIcon) { _, newValue in
                    try? DockActivationBridge.setDockEnabled(newValue)
                }

            // FR-120/FR-121 (T296): per-shortcut recorder.
            Section("Global Shortcuts") {
                ForEach(LocalPreferences.ShortcutAction.allCases, id: \.self) { action in
                    ShortcutRecorderRow(action: action)
                }
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
                LabeledContent("Accessibility") {
                    HStack(spacing: 8) {
                        statusLabel(accessibilityPermissionStatus)
                        permissionActionButtons(for: .accessibility)
                    }
                }
                if let accessibilityRequestResult {
                    Label(accessibilityRequestResult, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Permissions are requested only when you use the related feature (FR-131).")
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

// MARK: - ShortcutRecorderRow (T296, FR-120/FR-121)

/// One configurable global shortcut: current binding + record/clear.
struct ShortcutRecorderRow: View {
    let action: LocalPreferences.ShortcutAction

    @State private var isRecording = false
    @State private var currentKey: GlobalShortcutKey?
    @State private var currentRegistration: GlobalShortcutRegistration?
    @State private var statusMessage: String?
    @State private var eventMonitor: Any?

    private let preferences = LocalPreferences()

    var body: some View {
        LabeledContent(action.displayName) {
            HStack(spacing: 8) {
                if isRecording {
                    Text("Press keys…")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else if let currentKey {
                    Text(shortcutDisplay(currentKey))
                        .font(.system(.body, design: .monospaced))
                } else {
                    Text("Not set")
                        .foregroundStyle(.secondary)
                }

                Button(isRecording ? "Cancel" : "Record…") {
                    if isRecording { stopRecording() } else { startRecording() }
                }
                .controlSize(.small)

                if currentKey != nil && !isRecording {
                    Button("Clear") {
                        if let registration = currentRegistration {
                            try? GlobalShortcuts.unregister(registration)
                            currentRegistration = nil
                        }
                        preferences.setShortcutKey(nil, for: action)
                        currentKey = nil
                    }
                    .controlSize(.small)
                }
            }
        }
        .onAppear {
            currentKey = preferences.shortcutKey(for: action)
        }
        .onDisappear {
            stopRecording()
        }
        if let statusMessage {
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func startRecording() {
        isRecording = true
        statusMessage = nil
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let characters = event.charactersIgnoringModifiers, characters.count == 1 else {
                return event
            }
            // Escape cancels recording.
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let key = GlobalShortcutKey(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers(from: event.modifierFlags))
            finishRecording(key)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func finishRecording(_ key: GlobalShortcutKey) {
        stopRecording()
        do {
            // FR-121: registration failure (conflict) is surfaced, never
            // silently replaced.
            if let previous = currentRegistration {
                try? GlobalShortcuts.unregister(previous)
            }
            let registration = try GlobalShortcuts.register(key) { _ in
                Task { @MainActor in
                    ShortcutDispatcher.dispatch(action)
                }
            }
            currentRegistration = registration
            preferences.setShortcutKey(key, for: action)
            currentKey = key
            statusMessage = nil
        } catch {
            statusMessage = String(localized: "That shortcut is already in use.")
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        return modifiers
    }

    private func shortcutDisplay(_ key: GlobalShortcutKey) -> String {
        var parts: [String] = []
        if key.modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if key.modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if key.modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if key.modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        let character = key.keyCode == 45 ? "N" : "\(key.keyCode)"
        parts.append(character)
        return parts.joined()
    }
}

/// Dispatches a configured global shortcut to its action (T296).
@MainActor
public enum ShortcutDispatcher {
    public static func dispatch(_ action: LocalPreferences.ShortcutAction) {
        switch action {
        case .toggleLibrary:
            NSApplication.shared.activate(ignoringOtherApps: true)
        case .newBlankNote:
            NotificationCenter.default.post(name: .stickyRequestNewBlankNote, object: nil)
        case .captureRegion:
            NotificationCenter.default.post(name: .stickyRequestCaptureRegion, object: nil)
        case .captureWindow:
            NotificationCenter.default.post(name: .stickyRequestCaptureWindow, object: nil)
        case .clipboardNote:
            NotificationCenter.default.post(name: .stickyRequestClipboardNote, object: nil)
        case .searchAll:
            NSApplication.shared.activate(ignoringOtherApps: true)
        case .toggleNoteWindows:
            NotificationCenter.default.post(name: .stickyToggleNoteWindows, object: nil)
        }
    }
}

extension Notification.Name {
    static let stickyRequestNewBlankNote = Notification.Name("sticky.requestNewBlankNote")
    static let stickyRequestCaptureRegion = Notification.Name("sticky.requestCaptureRegion")
    static let stickyRequestCaptureWindow = Notification.Name("sticky.requestCaptureWindow")
    static let stickyRequestClipboardNote = Notification.Name("sticky.requestClipboardNote")
    static let stickyToggleNoteWindows = Notification.Name("sticky.toggleNoteWindows")
}
