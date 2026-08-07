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
        .frame(width: 460, height: 400)
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
