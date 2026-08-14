import Foundation
import Domain

// MARK: - Settings policies (003 T044-T050, FR-050/FR-051/FR-052/FR-055/FR-056; Rev 2 2026-08-14)
//
// Testable policy sources for the Settings architecture (asserted by
// T039/T041/T042/T043 and the Rev 2 T175 policy tests): native toolbar-style
// tab navigation over three logical areas (General/Sync/Privacy — Rev 2),
// a STABLE window shell whose geometry never depends on the selected tab
// (FR-051 Rev 2), failure handling, and the single "note font" concept. The
// views consult these; the tests assert them.
//
// Rev 2 (2026-08-14): the window shell is stable by design — switching tabs
// MUST NOT resize the window, the window MUST NOT shrink below the minimum
// that keeps the primary navigation expanded, and only the Sync pane (the
// one that can actually overflow) uses an internal scrolling container.

public enum SettingsLayoutPolicy {
    /// FR-050: native toolbar-style tab navigation (macOS 14+ TabView).
    public static let usesNativeToolbarTabs = true
    /// FR-050 (Rev 2): the three logical areas. Fonts folded into General's
    /// Notes section; Permissions renamed Privacy.
    public static let logicalAreas = ["General", "Sync", "Privacy"]
}

/// The implementation-level window-shell policy (FR-051 Rev 2 behavior).
/// The SPEC asserts behavior only (stable geometry across tab switches, no
/// navigation collapse at the minimum width, default size shows
/// General/Privacy completely, Sync overflows into an internal scroll
/// region); these numbers are the current implementation values and may be
/// tuned without a spec change.
public enum SettingsWindowPolicy {
    /// Stable default window size (points).
    public static let defaultWidth: CGFloat = 640
    public static let defaultHeight: CGFloat = 560
    /// Minimum window size (points) — keeps the three text tabs expanded in
    /// en and zh-Hans and shows General/Privacy fully.
    public static let minimumWidth: CGFloat = 600
    public static let minimumHeight: CGFloat = 440
    /// FR-051 Rev 2: switching tabs never changes window geometry.
    public static let windowSizeStableAcrossTabs = true
    /// Only tabs that can actually overflow (Sync) get a scrolling
    /// container; General/Privacy must not introduce one preemptively.
    public static let onlyOverflowingTabsScroll = true
    /// The minimum width keeps the primary (text) navigation expanded —
    /// no compact icon fallback UI exists or is planned.
    public static let navigationNeverCollapsesAtMinimumWidth = true
}

public enum SettingsFailurePolicy {
    /// The failure-handling mode for a settings-panel load failure.
    public enum FailureMode: Sendable {
        case nonBlockingNotice
        case preserveAndReport
    }
    /// CHK031: load failure → non-blocking localized notice, app continues.
    public static let onLoadFailure = FailureMode.nonBlockingNotice
    /// CHK031: save failure preserves user data and reports.
    public static let onSaveFailure = FailureMode.preserveAndReport
    /// FR-011a extension: the notice is localized (user-facing, no codes).
    public static let noticeIsLocalized = true
}

public enum ShortcutRecorderPolicy {
    /// FR-121: conflicts reported clearly.
    public static let conflictReportedClearly = true
    /// FR-121: never silently replace an existing binding.
    public static let neverSilentlyReplaces = true
    /// FR-052: clear + reset available.
    public static let supportsClear = true
    public static let supportsReset = true
    /// FR-052: Escape cancels recording; fully keyboard-operable.
    public static let escapeCancelsRecording = true
    public static let keyboardOperable = true
}

public enum FontPreferenceUI {
    /// FR-055 (Rev 3): ONE user-facing "note body font" concept.
    public static let singleNoteFontConcept = true
    /// FR-055: no implementation typography terms in the user surface.
    public static let usesImplementationTypographyTerms = false
    /// FR-055: the primary family gets a system fallback automatically.
    public static let systemFallbackProvided = true
    /// FR-055 (Rev 3): a meaningful bilingual MULTI-LINE preview sample —
    /// text spacing only affects inter-line spacing, so a single-line
    /// sample cannot preview it. Not localized: it is a fixed sample string
    /// for both languages (Latin + CJK mixed rendering).
    public static let bilingualPreviewSample = "The quick brown fox jumps over the lazy dog.\n这是便签正文的预览文本。\n第二行文字用于预览行间距效果。"
    public static let bilingualPreviewEnabled = true
}

// MARK: - NoteFontChoicePresentation (Rev 3, 2026-08-14)

/// Pure presentation for the "Note body font" choice (FR-055/055a Rev 3):
/// maps the stored `FontPreference?` to a menu selection over the system
/// font-family list. `nil` = "System Default" (the macOS system font — the
/// reset semantics unchanged, 001 FR-043 storage key untouched).
public enum NoteFontChoicePresentation {
    /// The first menu option — the unset state.
    public static let systemDefaultTitle = String(localized: "System Default")

    /// The full option list: "System Default" + the system families sorted
    /// case-insensitively, with the STORED family appended (when the running
    /// system no longer provides it) so the selection binding never dangles.
    public static func options(families: [String], storedFamily: String?) -> [String] {
        let sorted = families.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        var list = [systemDefaultTitle]
        list.append(contentsOf: sorted)
        if let storedFamily, !sorted.contains(storedFamily), storedFamily != systemDefaultTitle {
            list.append(storedFamily)
        }
        return list
    }

    /// The picker selection for a stored preference (`nil` → System Default).
    public static func selectedOption(for storedFamily: String?) -> String {
        storedFamily ?? systemDefaultTitle
    }

    /// The stored family a selected option represents (`nil` for System
    /// Default — clears the preference).
    public static func family(from option: String) -> String? {
        option == systemDefaultTitle ? nil : option
    }
}

/// FR-055 (Rev 3): the card body preview follows the user's body font
/// family; the card TITLE keeps the system headline (information hierarchy).
public enum CardBodyFont {
    /// The family the card body preview renders with; `nil` = system caption.
    public static func previewFamily(for preference: FontPreference?) -> String? {
        preference?.primaryFamily
    }
}

// MARK: - SyncSchedulePresentation (003 T185, FR-053 Rev 3)

/// The periodic-sync schedule presentation. Rev 3: the schedule is a
/// device-local preference (001 FR-152 — never touches remote state), so a
/// locked vault MUST NOT disable configuring it; only the automatic-sync
/// master switch does (FR-053 Rev 3 "disable only what is truly
/// non-executable").
public enum SyncSchedulePresentation {
    /// Whether the Periodic sync picker is enabled.
    public static func periodicPickerEnabled(autoSyncEnabled: Bool, isVaultUnlocked: Bool) -> Bool {
        autoSyncEnabled
    }
}

// MARK: - SyncLocationPresentation (Settings polish round 2/3, 2026-08-14)

/// Display-only composition of the user-facing storage location.
///
/// The verified persisted schema (data-model.md §VaultConfiguration, and
/// every app-side writer in this repo's history) stores ONLY the
/// user-chosen folder in `RedactedSyncConfig.prefix`; the vault locator is
/// composed at provider construction and never persisted. Display rules are
/// therefore schema-based, not shape-guessing:
///
/// 1. A LEADING segment equal to `vaultLocator` (or
///    `replacedFromVaultLocator`) is a legacy/foreign auto-generated write —
///    stripped.
/// 2. Any REMAINING segment satisfying the repo's own structural predicate
///    `RemoteLayout.isOpaque` (the canonical generated-namespace shape)
///    means the persisted prefix does not conform to the user-prefix schema
///    and the user's original path cannot be recovered reliably: `location`
///    returns nil (honest degradation — the caller shows provider-only copy
///    and keeps the technical path in Advanced). We never invent a path.
public enum SyncLocationPresentation {

    /// The user-facing storage location for a configuration: bucket/prefix
    /// (S3) or host+path/prefix (WebDAV), legacy locator segments stripped.
    /// `nil` when the persisted prefix does not conform to the schema (see
    /// rule 2) — the caller degrades to provider-only copy.
    public static func location(for configuration: VaultConfiguration) -> String? {
        let base: String
        switch configuration.providerType {
        case .webdav:
            base = endpointHost(configuration.providerConfig.endpoint)
        case .s3:
            base = configuration.providerConfig.bucket
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? configuration.providerConfig.endpoint
        }

        let raw = configuration.providerConfig.prefix ?? ""
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return base }

        var segments = trimmed
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        if let first = segments.first,
           first == configuration.vaultLocator || first == configuration.replacedFromVaultLocator {
            segments.removeFirst()
        }
        guard !segments.isEmpty else { return base }
        // Rule 2: an opaque generated-namespace segment anywhere in the
        // remainder → schema non-conformance → honest degradation.
        if segments.contains(where: { RemoteLayout.isOpaque($0) }) {
            return nil
        }
        return "\(base)/\(segments.joined(separator: "/"))"
    }

    /// The full technical path (protocol-level, unshortened) — for Advanced /
    /// diagnostics only, never the default Storage display.
    public static func technicalPath(for configuration: VaultConfiguration) -> String {
        let base: String
        switch configuration.providerType {
        case .webdav:
            base = endpointHost(configuration.providerConfig.endpoint)
        case .s3:
            base = configuration.providerConfig.bucket
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? configuration.providerConfig.endpoint
        }
        let raw = configuration.providerConfig.prefix ?? ""
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? base : "\(base)/\(trimmed)"
    }

    /// Endpoint without the URL scheme for display (e.g.
    /// "https://example.com/dav/" → "example.com/dav").
    public static func endpointHost(_ endpoint: String) -> String {
        guard let url = URL(string: endpoint), let host = url.host else { return endpoint }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? host : "\(host)/\(path)"
    }
}

// MARK: - VaultIDPresentation (Settings polish round 3, 2026-08-14)

/// Active presentation shortening for the Vault ID row. This is NOT overflow
/// truncation (which never triggers when the row has room): the UI shows a
/// fixed short form, while Copy / help always expose the full ID.
public enum VaultIDPresentation {
    /// "1870ff55…c5299"; short values pass through unchanged; empty → "—".
    public static func abbreviated(_ id: String) -> String {
        guard !id.isEmpty else { return "—" }
        guard id.count > 13 else { return id }
        return "\(id.prefix(8))…\(id.suffix(5))"
    }
}
