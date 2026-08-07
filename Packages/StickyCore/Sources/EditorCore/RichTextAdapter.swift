import Foundation
import Domain

// MARK: - RichTextAdapter (T161)
//
// Per tasks.md T161 and plan §Editor architecture: an isolated adapter
// converting between SwiftUI attributed state ↔ canonical rich-text document
// ↔ searchable plain text. Only application-supported formatting enters
// storage (FR-053); unsupported attributes are stripped. Unicode is
// normalized to NFC at the canonical boundary (research.md R16).
//
// The SwiftUI `AttributedString` side lives in the App layer (SwiftUI is not
// importable here); this EditorCore core handles the canonical ↔ plain-text
// ↔ mark-map conversions that are testable without UI. The App layer's
// `RichTextBlockView` bridges SwiftUI attributed text into these types and
// back (single source of truth for the mark set).

/// The supported inline marks as a stable set (mirrors RichTextMark).
public typealias SupportedMarks = Set<RichTextMark>

/// Converts canonical rich-text documents to/from plain text and maps the
/// supported mark set. Foundation-only, IME-safe by construction (no text
/// mutation here — only reading canonical state).
public enum RichTextAdapter {

    /// The canonical plain text of a document (NFC-normalized).
    public static func plainText(of document: RichTextDocument) -> String {
        UnicodeNormalization.nfc(document.text)
    }

    /// Builds a canonical document from plain text with no formatting.
    /// Paragraphs are split on newlines; each becomes a body paragraph.
    /// Used when pasting plain text / creating fresh blocks.
    public static func document(fromPlainText text: String) -> RichTextDocument {
        let normalized = UnicodeNormalization.nfc(text)
        guard !normalized.isEmpty else { return .empty }
        let scalars = normalized.unicodeScalars

        // Split into lines by scalar offsets.
        var paragraphs: [RichTextParagraph] = []
        var lineStart = 0
        var index = 0
        var lineCount = 0
        var lineEnds: [(start: Int, end: Int)] = []
        for scalar in scalars {
            if scalar == "\n" {
                lineEnds.append((lineStart, index))
                lineStart = index + 1
                lineCount += 1
            }
            index += 1
        }
        lineEnds.append((lineStart, index))  // last (possibly empty) line

        for line in lineEnds {
            guard line.end > line.start else { continue }
            paragraphs.append(
                RichTextParagraph(startScalar: line.start, endScalar: line.end, style: .body, runs: [])
            )
        }
        return RichTextDocument(text: normalized, paragraphs: paragraphs)
    }

    /// Maps the supported mark set to canonical runs over a plain-text
    /// range. Produces one run per contiguous mark-set change. Used when
    /// converting SwiftUI attributed text into canonical form.
    public static func runs(
        for marks: SupportedMarks,
        range: Range<Int>,
        link: String? = nil,
        hardBreak: Bool = false
    ) -> [RichTextRun] {
        guard !range.isEmpty else { return [] }
        return [
            RichTextRun(
                startScalar: range.lowerBound,
                endScalar: range.upperBound,
                marks: marks,
                link: link,
                hardBreak: hardBreak
            )
        ]
    }

    /// Collects the distinct mark sets used across a document (for the App
    /// layer's toolbar state).
    public static func distinctMarks(in document: RichTextDocument) -> SupportedMarks {
        var marks: SupportedMarks = []
        for paragraph in document.paragraphs {
            for run in paragraph.runs {
                marks.formUnion(run.marks)
            }
        }
        return marks
    }

    /// Strips unsupported attributes from a candidate mark set (FR-053:
    /// copy/paste output contains only supported formatting). Any mark not
    /// in `RichTextMark.allCases` is dropped.
    public static func supportedOnly(_ marks: Set<String>) -> SupportedMarks {
        let supported = Set(RichTextMark.allCases.map(\.rawValue))
        return Set(marks.compactMap { RichTextMark(rawValue: $0) }.filter { supported.contains($0.rawValue) })
    }

    /// Validates a document's paragraph/run structure, returning a sanitized
    /// reason when invalid (offsets out of range, overlapping runs, etc.).
    public static func validate(_ document: RichTextDocument) -> String? {
        let scalarCount = document.text.unicodeScalars.count
        for paragraph in document.paragraphs {
            guard paragraph.startScalar >= 0, paragraph.endScalar <= scalarCount,
                  paragraph.startScalar <= paragraph.endScalar else {
                return "paragraph range out of bounds"
            }
            for run in paragraph.runs {
                guard run.startScalar >= paragraph.startScalar,
                      run.endScalar <= paragraph.endScalar,
                      run.startScalar <= run.endScalar else {
                    return "run range out of bounds"
                }
            }
        }
        return nil
    }
}
