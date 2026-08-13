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
    /// FR-055: ONE user-facing "note font" concept.
    public static let singleNoteFontConcept = true
    /// FR-055: no implementation typography terms in the user surface.
    public static let usesImplementationTypographyTerms = false
    /// FR-055: the primary family gets a system fallback automatically.
    public static let systemFallbackProvided = true
    /// FR-055: a meaningful bilingual preview sample.
    public static let bilingualPreviewSample = "Aa 中文"
    public static let bilingualPreviewEnabled = true
}

// MARK: - SyncLocationPresentation (Settings polish round 2, 2026-08-14)

/// Display-only composition of the user-facing storage location.
///
/// Current builds persist ONLY the user-chosen folder in
/// `RedactedSyncConfig.prefix` (the vault locator is composed at provider
/// construction time, never persisted — verified against every app-side
/// writer in this repo's history). A persisted prefix whose LEADING segment
/// equals the vault locator is therefore a legacy/foreign write with the
/// auto-generated layout `<locator>` or `<locator>/<user-folder>…`; only
/// that leading segment is stripped for display. Everything else — ordinary
/// user prefixes, user-typed 32-hex segments, the locator in any
/// non-leading position — is kept verbatim. This is structural legacy-layout
/// recognition, NOT generic locator filtering.
public enum SyncLocationPresentation {

    /// The persisted prefix with the legacy leading locator segment removed
    /// (nil when nothing user-meaningful remains).
    public static func userPrefix(prefix: String?, vaultLocator: String) -> String? {
        guard let prefix, !prefix.isEmpty else { return nil }
        let trimmed = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        let segments = trimmed
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        if segments.first == vaultLocator {
            let rest = segments.dropFirst()
            return rest.isEmpty ? nil : rest.joined(separator: "/")
        }
        return trimmed
    }

    /// The user-facing storage location for a configuration: bucket/prefix
    /// (S3) or host+path/prefix (WebDAV), with the legacy locator segment
    /// stripped. Never includes the opaque vault locator.
    public static func location(for configuration: VaultConfiguration) -> String {
        let prefix = userPrefix(
            prefix: configuration.providerConfig.prefix,
            vaultLocator: configuration.vaultLocator
        )
        switch configuration.providerType {
        case .webdav:
            let host = endpointHost(configuration.providerConfig.endpoint)
            if let prefix {
                return "\(host)/\(prefix)"
            }
            return host
        case .s3:
            let bucket = configuration.providerConfig.bucket
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? configuration.providerConfig.endpoint
            if let prefix {
                return "\(bucket)/\(prefix)"
            }
            return bucket
        }
    }

    /// Endpoint without the URL scheme for display (e.g.
    /// "https://example.com/dav/" → "example.com/dav").
    public static func endpointHost(_ endpoint: String) -> String {
        guard let url = URL(string: endpoint), let host = url.host else { return endpoint }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? host : "\(host)/\(path)"
    }
}
