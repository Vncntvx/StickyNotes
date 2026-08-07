import SwiftUI
import Domain

// MARK: - ReadableTheme (T165, FR-042/FR-040a/FR-041a/FR-043a)
//
// Per tasks.md T165 and spec FR-030/FR-040a/FR-041a/FR-042/FR-043a: dynamic
// readable foreground colors + contrast adaptation. Custom colors failing
// contrast are adjusted or rejected (FR-042). The Domain projection
// (NoteAppearance) computes the foreground against the effective composited
// background; this view layer applies it.

/// Renders the Domain `NoteAppearance` as SwiftUI colors + fonts.
public enum ReadableTheme {

    /// The note background color (FR-040a canonical hex, clamped opacity per
    /// FR-041a).
    public static func background(for note: Note) -> Color {
        let appearance = NoteAppearance.projecting(from: note)
        return Color(
            red: appearance.background.red,
            green: appearance.background.green,
            blue: appearance.background.blue,
            opacity: appearance.opacity
        )
    }

    /// The readable foreground (black/white per FR-042 contrast).
    public static func foreground(for note: Note) -> Color {
        let appearance = NoteAppearance.projecting(from: note)
        return Color(
            red: appearance.foreground.red,
            green: appearance.foreground.green,
            blue: appearance.foreground.blue,
            opacity: 1.0
        )
    }

    /// The per-note text size in points (FR-043a: 9–24).
    public static func textSize(for note: Note) -> CGFloat {
        CGFloat(NoteAppearance.TextSizeBounds.clamped(note.textSize))
    }

    /// Whether the note's custom color fails contrast (the App layer then
    /// rejects it with an explanation — FR-042).
    public static func customColorFailsContrast(_ note: Note) -> Bool {
        guard note.colorKey == .custom else { return false }
        return !NoteAppearance.projecting(from: note).meetsMinimumContrast
    }
}
