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
}
