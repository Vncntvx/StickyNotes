import Foundation

// MARK: - HTTP-date parsing (R3.6, remediation roadmap 2026-08-14)
//
// The three adapters previously carried near-identical DateFormatter
// blocks (WebDAVProvider.parseDate / WebDAVProvider.parseHTTPDate /
// S3Provider.parseHTTPDate). Converged to this single parser — RFC 1123
// (the HTTP-date format both providers receive) plus ISO-8601 for
// tolerant clients.

/// Shared HTTP-date parsing for the sync adapters.
public enum SyncHTTPDateParser {
    /// Parses an HTTP-date (RFC 1123) or ISO-8601 string; nil when absent
    /// or unparseable (callers treat nil as "unknown modified time").
    public static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        for format in ["EEE, dd MMM yyyy HH:mm:ss 'GMT'", "yyyy-MM-dd'T'HH:mm:ssZZZZZ"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}
