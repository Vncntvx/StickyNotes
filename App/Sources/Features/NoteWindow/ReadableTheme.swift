import SwiftUI
import Domain

// MARK: - ReadableTheme (003 T010, FR-042/FR-040a/FR-041a/FR-043a/FR-033)
//
// Per tasks.md T010 and spec FR-033: foreground auto-adjustment now reads
// the ACTUAL rendered values from `NotePalette` (light/dark designed
// values) instead of the Domain source literals. Built-in colors resolve
// through the palette (per-appearance design); custom colors keep the
// Domain projection path (001 FR-042 semantics preserved — custom +
// transparency + Increase Contrast combinations auto-adjust the
// foreground and are never rejected).

/// Renders the note appearance as SwiftUI colors + fonts.
public enum ReadableTheme {

    /// The note background color. Built-in keys resolve through the
    /// palette's per-appearance design (FR-030/031); custom colors use the
    /// Domain projection (001 FR-040a/FR-041a).
    public static func background(for note: Note) -> Color {
        if let paletteKey = NotePalette.paletteKey(for: note.colorKey) {
            // Dynamic per-appearance palette background; apply the note's
            // opacity on top (FR-041a).
            return NotePalette.dynamicColor(for: paletteKey).opacity(note.transparency)
        }
        let appearance = NoteAppearance.projecting(from: note)
        return Color(
            red: appearance.background.red,
            green: appearance.background.green,
            blue: appearance.background.blue,
            opacity: appearance.opacity
        )
    }

    /// The readable foreground (black/white per FR-042 contrast). Built-in
    /// keys use the palette's auto-adjusted foreground; custom colors use
    /// the Domain contrast projection — never rejected (FR-033).
    public static func foreground(for note: Note) -> Color {
        if let paletteKey = NotePalette.paletteKey(for: note.colorKey) {
            return NotePalette.dynamicForeground(for: paletteKey)
        }
        let appearance = NoteAppearance.projecting(from: note)
        return Color(
            red: appearance.foreground.red,
            green: appearance.foreground.green,
            blue: appearance.foreground.blue,
            opacity: 1.0
        )
    }

    /// The secondary text color on the note surface (palette-driven for
    /// built-ins; Domain black/white at 90% for custom colors).
    public static func secondaryForeground(for note: Note) -> Color {
        if let paletteKey = NotePalette.paletteKey(for: note.colorKey) {
            return NotePalette.dynamicSecondaryForeground(for: paletteKey)
        }
        let appearance = NoteAppearance.projecting(from: note)
        return Color(
            red: appearance.foreground.red,
            green: appearance.foreground.green,
            blue: appearance.foreground.blue,
            opacity: 0.9
        )
    }

    /// The per-note text size in points (FR-043a: 9–24).
    public static func textSize(for note: Note) -> CGFloat {
        CGFloat(NoteAppearance.TextSizeBounds.clamped(note.textSize))
    }

    /// Whether the note's custom color fails contrast (FR-042 — the App
    /// layer adjusts the foreground rather than rejecting; this helper
    /// reports the raw outcome for diagnostics).
    public static func customColorFailsContrast(_ note: Note) -> Bool {
        guard note.colorKey == .custom else { return false }
        return !NoteAppearance.projecting(from: note).meetsMinimumContrast
    }
}
