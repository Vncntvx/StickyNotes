import Foundation

// MARK: - Widget visibility (T095)
//
// Per tasks.md T095 and plan §Widgets / research.md R14: widget-ineligible
// notes expose NOTHING (no title/body/todo/screenshot/summary) in timelines,
// previews, placeholders, or snapshots. This value-type rule is the single
// place the privacy gate lives so every widget surface (timeline, preview,
// placeholder, snapshot, logs) applies the identical policy.

/// The privacy gate for widget surfaces. Language-neutral, Sendable, and
/// unit-testable without any widget machinery (constitution VI).
public enum WidgetVisibility {

    /// What a widget surface may render for a note.
    public enum Surface: Sendable, Equatable {
        /// The note's actual content (title/summary/todos…).
        case content
        /// A privacy-safe placeholder ("Unavailable" style) that reveals
        /// nothing about the note.
        case placeholder
        /// Nothing at all (empty surface).
        case none
    }

    /// The widget surface a note may expose.
    ///
    /// A note is content-eligible ONLY when ALL of:
    /// - `widgetEligible` (per-note opt-in, FR-112);
    /// - `lifecycleState == .active` (deleted/trashed/conflict-copy notes
    ///   are never exposed — plan §Widgets, research.md R14);
    /// - the note is not a conflict copy (`conflictOriginNoteId == nil`).
    ///
    /// Everything else is a placeholder at most — never content.
    public static func surface(
        for note: Note,
        widgetEligible: Bool,
        schemaVersionKnown: Bool
    ) -> Surface {
        // Schema mismatch: read-only placeholders, never content
        // (research.md R6; plan §Local storage).
        guard schemaVersionKnown else { return .placeholder }

        guard widgetEligible else { return .none }
        guard note.widgetEligible else { return .none }
        guard note.lifecycleState == .active else { return .placeholder }
        guard note.conflictOriginNoteId == nil else { return .placeholder }
        return .content
    }

    /// Convenience for `Note` rows coming straight from persistence.
    public static func surface(for note: Note, schemaVersionKnown: Bool = true) -> Surface {
        surface(for: note, widgetEligible: true, schemaVersionKnown: schemaVersionKnown)
    }

    /// Whether `note` may appear in a widget timeline at all (even as a
    /// placeholder). Returns false only for ineligible notes (nothing is
    /// exposed for them anywhere, including logs — research.md R14).
    public static func mayAppearInTimelines(for note: Note) -> Bool {
        note.widgetEligible
    }
}
