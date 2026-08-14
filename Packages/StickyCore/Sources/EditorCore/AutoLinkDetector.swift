import Foundation
import Domain

// MARK: - AutoLinkDetector (T143/T148)
//
// Per tasks.md T143/T148 and spec FR-050: automatic link detection for web
// URLs, email addresses, and telephone numbers, feeding the canonical
// rich-text `link` mark. No false positives inside code blocks (FR-050).
//
// Pure detection (testable headlessly); the App layer wires results into the
// editor's canonical rich-text conversion (RichTextAdapter → link mark).

/// A detected link inside a text range.
public struct DetectedLink: Sendable, Equatable {
    /// Scalar range of the detected text within the document.
    public let range: Range<Int>
    /// The link target (URL string for web/email/phone).
    public let target: String

    public init(range: Range<Int>, target: String) {
        self.range = range
        self.target = target
    }
}

/// Detects web URLs, email addresses, and telephone numbers (FR-050).
public enum AutoLinkDetector {

    /// Detects links in a text. `insideCodeBlock` suppresses detection
    /// (FR-050: no false positives inside code blocks except the closing
    /// fence is a Markdown concern, not link detection).
    public static func detectLinks(in text: String, insideCodeBlock: Bool) -> [DetectedLink] {
        guard !insideCodeBlock else { return [] }
        // R3.5 (remediation roadmap 2026-08-14): the previous implementation
        // was a hand-rolled character scanner with ad-hoc regexes — it
        // destroyed phone formatting ("+" + digits produced meaningless
        // tel: targets for local numbers) and emitted scheme-less www
        // targets. NSDataDetector is the platform detector (link +
        // phoneNumber) and stays Foundation-only, so the EditorCore module
        // boundary is untouched.
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
                | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
        ) else { return [] }
        let nsText = text as NSString
        var results: [DetectedLink] = []
        detector.enumerateMatches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) { match, _, _ in
            guard let match, let utf16Range = Range(match.range, in: text) else { return }
            let target: String
            if let url = match.url {
                target = url.absoluteString
            } else if let phone = match.phoneNumber {
                // E.164 for international numbers (strip separators);
                // LOCAL numbers keep their original formatting — the old
                // scanner prepended "+" to everything, producing
                // meaningless tel: targets for local numbers (R3.5).
                if phone.hasPrefix("+") {
                    let digits = phone.filter { $0.isNumber || $0 == "+" }
                    target = "tel:\(digits)"
                } else {
                    target = "tel:\(phone)"
                }
            } else {
                return
            }
            let scalars = text.unicodeScalars
            let lower = scalars.distance(from: scalars.startIndex, to: utf16Range.lowerBound)
            let upper = scalars.distance(from: scalars.startIndex, to: utf16Range.upperBound)
            results.append(DetectedLink(range: lower..<upper, target: target))
        }
        return results
    }

    /// Attempts to match a link starting exactly at the beginning of the
    /// string. Returns (matchedScalarCount, target) or nil.
    static func match(atStartOf s: String) -> (Int, String)? {
        // Bound the scan window (links are short; avoids pathological scans
        // on huge strings).
        let window = s.unicodeScalars.prefix(2048)
        let lower = String(String.UnicodeScalarView(Array(window)))
        // Web URLs: scheme://…
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return matchURL(lower)
        }
        // www. URLs without scheme.
        if lower.hasPrefix("www.") {
            return matchWWW(lower)
        }
        // Email addresses.
        if let email = matchEmail(lower) {
            return email
        }
        // Telephone numbers.
        if let phone = matchPhone(lower) {
            return phone
        }
        return nil
    }

    private static func matchURL(_ s: String) -> (Int, String)? {
        // Consume until whitespace or punctuation that terminates a URL.
        let allowedEnd = CharacterSet(charactersIn: "!?.,;:()[]{}<>\"'")
        var end = s.startIndex
        for (offset, scalar) in s.unicodeScalars.enumerated() {
            if scalar == " " || scalar == "\n" || scalar == "\t" {
                end = s.index(s.startIndex, offsetBy: offset)
                break
            }
            if offset > 0, allowedEnd.contains(scalar), offset == s.unicodeScalars.count - 1 {
                end = s.index(s.startIndex, offsetBy: offset)
                break
            }
            if offset > 0, allowedEnd.contains(scalar),
               let next = s.unicodeScalars.index(s.startIndex, offsetBy: offset + 1, limitedBy: s.endIndex),
               next == s.endIndex {
                end = s.index(s.startIndex, offsetBy: offset)
                break
            }
            end = s.index(s.startIndex, offsetBy: offset + 1)
        }
        let matched = String(s[..<end])
        guard matched.count >= 8 else { return nil }
        // Trim trailing punctuation.
        var trimmed = matched
        while let last = trimmed.last, ".,;:!?)]}".contains(last) {
            trimmed.removeLast()
        }
        guard trimmed.count >= 8 else { return nil }
        return (trimmed.unicodeScalars.count, trimmed)
    }

    private static func matchWWW(_ s: String) -> (Int, String)? {
        // www.example.com/path — must contain a dot after "www."
        let tail = String(s.dropFirst(4))
        guard let dotIndex = tail.firstIndex(of: ".") else { return nil }
        guard tail.distance(from: tail.startIndex, to: dotIndex) >= 1 else { return nil }
        // Reuse URL matching on the http-prefixed string.
        return matchURL(s)
    }

    private static func matchEmail(_ s: String) -> (Int, String)? {
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
        guard let range = s.range(of: pattern, options: .regularExpression) else { return nil }
        let matched = String(s[range])
        return (matched.unicodeScalars.count, "mailto:\(matched)")
    }

    private static func matchPhone(_ s: String) -> (Int, String)? {
        // +1 (555) 123-4567 / 555-123-4567 / (555) 123-4567 with optional
        // country code. Must have 7+ digits.
        let pattern = #"^(\+[0-9]{1,3}[\s.-]?)?(\([0-9]{1,4}\)[\s.-]?)?[0-9]{2,4}[\s.-][0-9]{3,4}[\s.-]?[0-9]{0,4}"#
        guard let range = s.range(of: pattern, options: .regularExpression) else { return nil }
        let matched = String(s[range])
        let digits = matched.filter(\.isNumber)
        guard digits.count >= 7, digits.count <= 15 else { return nil }
        let normalized = "+" + digits  // E.164-ish (local numbers get +1 handling by the App layer)
        return (matched.unicodeScalars.count, "tel:\(normalized)")
    }
}
