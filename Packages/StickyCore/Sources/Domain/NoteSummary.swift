import Foundation

// MARK: - NoteSummary (T045)
//
// Per tasks.md T045 and plan §Search:
// - "generated-summary derivation (first meaningful content as temporary
//   display title)" — when a note has no manual title, the library shows
//   a generated summary derived from the note's first meaningful block
//   content. This summary is NEVER stored as the note's title (FR-045:
//   the generated summary is display-only, never silently persisted).
//
// Constitution IV: the generated summary is a *projection* of the canonical
// data, never a durable field. It feeds the SearchDocument.summary column
// so the source text is searchable, but it is not itself a stored title.

/// Derives a temporary display summary for a note from its first meaningful
/// block content. Used when `Note.title == nil`. The summary is NEVER stored
/// as `Note.title` (FR-045) — it's a projection.
public enum NoteSummary {

    /// Maximum number of characters in a generated summary. Long enough to
    /// be useful in a card grid, short enough not to dominate the card.
    public static let maxLength = 80

    /// Returns the generated summary for the note, or `nil` if the note has
    /// no meaningful content (the caller shows a placeholder string instead).
    ///
    /// The first meaningful block is the first non-empty rich-text/code/todo
    /// block by `sortKey`. File-ref/image/screenshot blocks contribute their
    /// display name / caption / "Screenshot" / "Image" if no text precedes
    /// them.
    public static func generatedSummary(for blocks: [Block]) -> String? {
        // Order by sortKey to find the "first" block.
        let ordered = blocks.sorted { $0.sortKey < $1.sortKey }

        for block in ordered {
            switch block.payload {
            case .richText(let doc):
                let trimmed = doc.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return clip(trimmed)
                }
            case .todo(let payload):
                let trimmed = payload.richText.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return clip(trimmed)
                }
            case .code(let payload):
                let trimmed = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return clip(trimmed)
                }
            case .fileReference(let payload):
                if !payload.displayName.isEmpty {
                    return clip(payload.displayName)
                }
            case .screenshot(let payload):
                if let caption = payload.caption, !caption.isEmpty {
                    return clip(caption)
                }
                return "Screenshot"
            case .image(let payload):
                if let caption = payload.caption, !caption.isEmpty {
                    return clip(caption)
                }
                return "Image"
            }
        }
        return nil
    }

    /// Returns `Note.title` if present, otherwise the generated summary, or
    /// `nil` if neither is available. The caller decides what placeholder
    /// string to show for `nil`.
    public static func displayTitle(note: Note, blocks: [Block]) -> String? {
        if let title = note.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        return generatedSummary(for: blocks)
    }

    /// Clips a string to `maxLength` characters on a word boundary when
    /// possible, appending an ellipsis if clipped.
    private static func clip(_ string: String) -> String {
        guard string.count > maxLength else { return string }
        let end = string.index(string.startIndex, offsetBy: maxLength)
        let prefix = String(string[..<end])
        // Try to break on a whitespace boundary for readability.
        if let lastSpace = prefix.lastIndex(of: " "), lastSpace > prefix.startIndex {
            let trimmed = String(prefix[..<lastSpace])
            return trimmed + "…"
        }
        return prefix + "…"
    }
}
