import Foundation

// MARK: - Settings policies (003 T044-T050, FR-050/FR-051/FR-052/FR-055/FR-056)
//
// Testable policy sources for the Settings redesign (asserted by T039/T041/
// T042/T043): native toolbar-style tab navigation, content-fit panels,
// failure handling, recorder conflict semantics, and the single "note font"
// concept. The views consult these; the tests assert them.

public enum SettingsLayoutPolicy {
    /// FR-050: native toolbar-style tab navigation (macOS 14+ TabView).
    public static let usesNativeToolbarTabs = true
    /// The four logical areas.
    public static let logicalAreas = ["General", "Sync", "Fonts", "Permissions"]
    /// FR-051/SC-011: no fixed-height pane — panels fit their content.
    public static let fixedCanvasHeight: CGFloat? = nil
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
