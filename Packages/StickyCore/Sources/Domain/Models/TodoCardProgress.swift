import Foundation

// MARK: - TodoCardProgress (T244, FR-072b)
//
// Per tasks.md T244 and spec FR-072b (clarified 2026-08-07): the card todo
// progress is "completed/total" (e.g. "12/45"); totals > 99 render as
// "99+ completed" (width safety while preserving the progress signal).
// Language-neutral formatting (constitution XIV); the App layer localizes
// surrounding text.

public enum TodoCardProgress {
    /// Returns the card progress string, or nil when there are no todos.
    public static func format(completed: Int, total: Int) -> String? {
        guard total > 0 else { return nil }
        if total > 99 { return "99+ completed" }
        return "\(completed)/\(total)"
    }
}
