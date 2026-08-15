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
        // R3.8: Date.FormatStyle replaces the per-call DateFormatter; the
        // abbreviated month + day (year when in a previous calendar year)
        // matches the previous "MMM d" / "MMM d, yyyy" output per-locale.
        let isPreviousYear = calendar.component(.year, from: date) < calendar.component(.year, from: now)
        if isPreviousYear {
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Locale-aware file size ("248 KB", "1.2 MB").
    public static func fileSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

}