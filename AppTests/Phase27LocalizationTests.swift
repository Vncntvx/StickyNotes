import Testing
import Foundation

// MARK: - Phase 27 localization tests (T295, FR-180a)
//
// Per tasks.md T295: the Phase 26/27 UI strings (Help view, sync settings,
// deletion toasts, editor block actions, shortcuts) must resolve from the
// localization catalogs in BOTH zh-Hans and en — no English-only fallback
// for zh-Hans users.

@Suite struct Phase27LocalizationTests {

    /// The keys added by Phase 26/27 (each must exist with both languages).
    private static let requiredKeys: [String] = [
        "Help", "Sticky Notes Help", "Menu-bar first", "Auto-save",
        "Keyboard shortcuts", "Markdown shortcuts", "Screenshots and files",
        "Synchronization", "Not configured", "Configured", "Automatic sync",
        "Remember unlocked vault on this Mac", "Sync Now", "Syncing…",
        "Moved to Trash", "Permanently Deleted", "Sync not configured",
        "Sync issue", "Retry", "Sync ready", "Add Todo", "Add Code Block",
        "Add File Reference…", "Capture Screenshot…", "Add Block",
        "Add Screenshot", "Capture Region…", "Capture Window…", "Todo",
        "Set as Cover", "Remove Cover", "Caption", "View", "Copy",
        "Save As…", "Remove", "Available", "Missing — relink to open",
        "File may have moved", "Relinked", "On another device",
        "Open file", "Reveal in Finder", "Copy Path", "Relink…",
        "Move File…", "Remove Reference", "Copy code", "Not set",
        "Record…", "Clear", "Press keys…", "That shortcut is already in use.",
        "Open/Close Library", "New Blank Note",
        "Capture Region into New Note", "Capture Window into New Note",
        "New Note from Clipboard", "Search All Notes",
        "Show/Hide Note Windows", "Add screenshot", "Add file reference",
        "Configure Synchronization", "Provider", "WebDAV", "S3-compatible",
        "Vault password", "Test Connection", "Configure", "Replace",
        "Configure Sync…", "Replace Repository…", "Remove Configuration…",
        "Export Diagnostic Bundle…",
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
