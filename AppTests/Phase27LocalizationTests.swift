import Testing
import Foundation

// MARK: - Phase 27 localization tests (T295, FR-180a)
//
// Per tasks.md T295: the Phase 26/27 UI strings (Help view, sync settings,
// deletion toasts, editor block actions) must resolve from the localization
// catalogs in BOTH zh-Hans and en — no English-only fallback for zh-Hans
// users. (Global-shortcut strings were removed with the feature 2026-08-10.)

@Suite struct Phase27LocalizationTests {

    /// The keys added by Phase 26/27 (each must exist with both languages).
    /// Rev 2 (2026-08-14): Settings copy changes — renamed keys replace the
    /// removed ones ("Configured" → resolver-driven "Up to Date" etc.).
    private static let requiredKeys: [String] = [
        "Help", "Sticky Notes Help", "Menu-bar first", "Auto-save",
        "Keyboard shortcuts", "Markdown shortcuts", "Screenshots and files",
        "Synchronization", "Not configured", "Up to Date",
        "Automatic Sync", "Sync changes automatically", "Periodic sync",
        "Off", "Every 5 minutes", "Every 15 minutes", "Every 30 minutes",
        "Every hour",
        "Keep sync unlocked on this Mac", "Sync Now", "Syncing…",
        "Moved to Trash", "Permanently Deleted", "Sync not configured",
        "Sync issue", "Retry", "Sync ready", "Add Todo",
        "Add File Reference…", "Capture Screenshot…", "Add Block",
        "Add Screenshot", "Capture Region…", "Capture Window…", "Todo",
        "Set as Cover", "Remove Cover", "Caption", "View", "Copy",
        "Save As…", "Remove", "Available", "Missing — relink to open",
        "File may have moved", "Relinked", "On another device",
        "Open file", "Reveal in Finder", "Copy Path", "Relink…",
        "Move File…", "Remove Reference", "Copy code",
        "New Note from Clipboard", "Show/Hide Note Windows",
        "Add screenshot", "Add file reference",
        "Configure Synchronization", "Provider", "WebDAV", "S3-compatible",
        "Vault password", "Test Connection", "Join", "Set Up",
        "Set Up Sync…", "Join Existing Vault…", "Join Another Vault…",
        "Set Up New Storage Location…", "Disconnect Sync…", "Manage…",
        "Export Diagnostic Bundle…", "Export Sync Profile…",
        "Last synced", "Storage", "Sync vault is locked", "Unlock…",
        "Unlock the vault to sync manually or resume automatic sync. Your notes on this Mac are still available.",
        "Screen Recording", "Not Granted", "Enable…",
        "Disconnect Sync?", "Disconnect",
        // Settings polish round 2 (2026-08-14)
        "Vault ID", "Copy Vault ID", "Copied.",
        // Settings polish round 3 (2026-08-14)
        "S3-compatible storage", "WebDAV storage", "Recovery",
        "Keeps sync unlocked using Keychain until you restart or lock the vault.",
        "When enabled, changes sync automatically. Periodic syncing is optional.",
        // Typography settings (Phase 5 + Rev 3, 2026-08-14)
        "Text Spacing", "Compact", "Default", "Relaxed",
        "Note Appearance", "Note body font", "System Default",
        // Trash ⋯ menu (003 T183, 2026-08-14)
        "More trash actions",
    ]

    @Test
    func phase26And27KeysExistInBothLanguages() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/Resources")
        let catalog = resources.appendingPathComponent("Localizable.xcstrings")
        guard let data = try? Data(contentsOf: catalog),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = json["strings"] as? [String: Any] else {
            Issue.record("catalog must exist and parse")
            return
        }

        for key in Self.requiredKeys {
            guard let entry = strings[key] as? [String: Any] else {
                Issue.record("missing catalog key: \(key)")
                continue
            }
            let localizations = (entry["localizations"] as? [String: Any]) ?? [:]
            #expect(localizations["en"] != nil, "\(key): missing en")
            #expect(localizations["zh-Hans"] != nil, "\(key): missing zh-Hans (FR-180a)")
        }
    }
}
