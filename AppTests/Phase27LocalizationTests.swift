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
        "Keyboard shortcuts", "Formatting", "Screenshots and files",
        "Synchronization", "Not configured", "Up to Date", "Automatic sync",
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
        "Set Up New Storage Location…", "Disconnect Sync…",
        "Export Diagnostic Bundle…", "Export Sync Profile…",
        "Last synced", "Storage", "Sync vault is locked", "Unlock…",
        "Screen Recording", "Not Granted", "Enable…",
        "Disconnect Sync?", "Disconnect",
        // Settings polish round 2 (2026-08-14)
        "Vault ID", "Copy Vault ID", "Copied.",
        // Settings polish round 3 (2026-08-14)
        "S3-compatible storage", "WebDAV storage", "Recovery",
        "Keeps sync unlocked using Keychain until you restart or lock the vault.",
        "When enabled, changes sync automatically. Periodic syncing is optional.",
        // Typography settings (Phase 5, 2026-08-14)
        "Text Spacing", "Compact", "Default", "Relaxed", "Reset",
        "Note Appearance",
        "That font family was not found on this Mac. Your existing preference is unchanged.",
        "Type a font family name — for example, Helvetica Neue. Empty means Default (the system font).",
    ]

    @Test
    func phase26And27KeysExistInBothLanguages() throws {
        // Queries the COMPILED localizations through Foundation's own
        // bundle mechanism (lproj sub-bundle + localizedString). The
        // previous implementation located `Localizable.xcstrings` via
        // `#filePath` — a source-tree path on the external volume — so
        // every test run triggered a TCC external-volume access prompt
        // (user feedback 2026-08-14); a first rewrite parsed the compiled
        // .strings with PropertyListSerialization, which mishandled the
        // UTF-16 XML format. The bundle query is both stable and
        // external-volume-free.
        let en = Self.loadStrings(localization: "en")
        let zh = Self.loadStrings(localization: "zh-Hans")
        for key in Self.requiredKeys {
            #expect(en?[key] != nil, "\(key): missing en")
            #expect(zh?[key] != nil, "\(key): missing zh-Hans (FR-180a)")
        }
    }

    /// Loads the compiled `Localizable.strings` for a localization. The
    /// compiled file is a UTF-16 XML plist whose declaration claims UTF-8 —
    /// PropertyListSerialization rejects the raw bytes, so normalize to
    /// UTF-8 first.
    private static func loadStrings(localization: String) -> [String: String]? {
        guard let url = Bundle.main.url(
            forResource: "Localizable", withExtension: "strings",
            subdirectory: nil, localization: localization
        ), let raw = try? Data(contentsOf: url),
           let text = String(data: raw, encoding: .utf16) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(
            from: Data(text.utf8), options: [], format: nil
        ) as? [String: String] else { return nil }
        return plist
    }
}
