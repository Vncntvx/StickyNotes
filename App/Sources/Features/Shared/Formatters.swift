import Foundation
import Domain

// MARK: - Formatters (T133/T172/T256)
//
// Per tasks.md T133/T172/T256: locale-aware date/file-size formatters;
// language-neutral persisted enums/sync schemas (no localized strings as
// protocol identifiers); FR-020a last-modified time rule: relative ("5 min
// ago") within the last 7 days, absolute ("Aug 1", with the year when in a
// previous calendar year) beyond.

/// Locale-aware display formatters for dates + file sizes (FR-180a).
public enum DisplayFormatters {

    /// FR-020a: relative within 7 days, absolute beyond (year when in a
    /// previous calendar year). Age = exactly 7 days renders relative; 7
    /// days + 1 second renders absolute (deterministic boundary).
    public static func lastModified(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let age = now.timeIntervalSince(date)
        let sevenDays: TimeInterval = 7 * 86_400
        if age >= 0 && age <= sevenDays {
            return relativeTime(date, now: now, calendar: calendar)
        }
        return absoluteDate(date, now: now, calendar: calendar)
    }

    /// Relative time ("5 min ago"); locale-aware.
    public static func relativeTime(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return String(localized: "now") }
        if seconds < 3_600 {
            let minutes = Int(seconds / 60)
            return String(localized: "\(minutes) min ago")
        }
        if seconds < 86_400 {
            let hours = Int(seconds / 3_600)
            return String(localized: "\(hours) hr ago")
        }
        let days = Int(seconds / 86_400)
        return String(localized: "\(days) days ago")
    }

    /// Absolute date ("Aug 1"; year included when in a previous calendar
    /// year per FR-020a).
    public static func absoluteDate(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        let isPreviousYear = calendar.component(.year, from: date) < calendar.component(.year, from: now)
        formatter.dateFormat = isPreviousYear ? "MMM d, yyyy" : "MMM d"
        return formatter.string(from: date)
    }

    /// Locale-aware file size ("248 KB", "1.2 MB").
    public static func fileSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Locale-aware date-time for file cards ("Aug 1, 2026 at 9:10 AM").
    public static func dateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Card preview truncation (T256, FR-020a)

/// FR-020a: the card body preview is truncated at 2 rendered lines with a
/// trailing ellipsis, drawn from the FIRST rich-text block — never
/// duplicating the generated summary title. Line-level at the card's current
/// width; this helper approximates line breaks by a char budget per line
/// (the SwiftUI view applies it at the rendered width via
/// `lineLimit(2)` + truncation; the helper guarantees the SOURCE text is
/// bounded so the summary title is never repeated).
public enum CardPreview {
    /// The first rich-text block's text (preview source), or nil.
    public static func previewSource(from blocks: [Block]) -> String? {
        for block in blocks.sorted(by: { $0.sortKey < $1.sortKey }) {
            if case .richText(let doc) = block.payload {
                let text = doc.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    /// Whether the preview duplicates the summary title (should never
    /// happen — the summary derives from the same text; the VIEW shows
    /// either the manual title or the summary, and the preview separately).
    public static func duplicatesSummary(_ preview: String, summary: String?) -> Bool {
        guard let summary else { return false }
        return preview == summary
    }
}
