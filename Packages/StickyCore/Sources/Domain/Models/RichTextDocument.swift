import Foundation

// MARK: - Canonical rich-text model (T014)
//
// Per contracts/rich-text.schema.json and research.md R16.
//
// The canonical rich-text model is a project-owned run/paragraph model — NOT
// an archived NSAttributedString/AttributedString. It stores only
// application-supported formatting. Text is Unicode scalars normalized to
// NFC; run boundaries are scalar offsets (NOT Swift String.Index, which is
// not stable across serialization).
//
// Schema version 1 (constitution IV — explicit, durable, versioned data).

/// The supported inline marks per contracts/rich-text.schema.json. Unsupported
/// private attributes MUST NOT appear in canonical rich text.
public enum RichTextMark: String, Sendable, Codable, CaseIterable {
    case bold
    case italic
    case underline
    case strikethrough
    case inlineCode
}

/// Paragraph style per contracts/rich-text.schema.json.
public enum ParagraphStyle: String, Sendable, Codable, CaseIterable {
    case body
    case heading
    case bullet
}

/// A contiguous text run within a paragraph, carrying optional marks, an
/// optional link, and an optional hard break at the run's end.
///
/// `startScalar`/`endScalar` are scalar offsets into the document's `text`
/// (Unicode scalars, NFC-normalized). Unstyled ranges need no run.
public struct RichTextRun: Sendable, Codable, Equatable, Hashable {
    public var startScalar: Int
    public var endScalar: Int
    public var marks: Set<RichTextMark>
    public var link: String?
    public var hardBreak: Bool

    public init(
        startScalar: Int,
        endScalar: Int,
        marks: Set<RichTextMark> = [],
        link: String? = nil,
        hardBreak: Bool = false
    ) {
        precondition(startScalar >= 0, "startScalar must be ≥ 0")
        precondition(endScalar >= 0, "endScalar must be ≥ 0")
        precondition(startScalar <= endScalar, "startScalar must be ≤ endScalar")
        self.startScalar = startScalar
        self.endScalar = endScalar
        self.marks = marks
        self.link = link
        self.hardBreak = hardBreak
    }
}

/// A paragraph covers a contiguous scalar range and carries paragraph-level
/// style plus ordered runs.
public struct RichTextParagraph: Sendable, Codable, Equatable, Hashable {
    public var startScalar: Int
    public var endScalar: Int
    public var style: ParagraphStyle
    public var runs: [RichTextRun]

    public init(
        startScalar: Int,
        endScalar: Int,
        style: ParagraphStyle,
        runs: [RichTextRun] = []
    ) {
        precondition(startScalar >= 0, "startScalar must be ≥ 0")
        precondition(endScalar >= 0, "endScalar must be ≥ 0")
        precondition(startScalar <= endScalar, "startScalar must be ≤ endScalar")
        self.startScalar = startScalar
        self.endScalar = endScalar
        self.style = style
        self.runs = runs
    }
}

/// The canonical rich-text document.
///
/// - `text`: full plain text in NFC, Unicode scalars. The source of truth
///   for characters; runs reference offsets into this string.
/// - `paragraphs`: ordered paragraphs covering contiguous scalar ranges.
///
/// Per contracts/rich-text.schema.json. Schema version 1.
public struct RichTextDocument: Sendable, Codable, Equatable, Hashable {
    /// Canonical schema version (constitution IV).
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var text: String
    public var paragraphs: [RichTextParagraph]

    public init(text: String, paragraphs: [RichTextParagraph], schemaVersion: Int = RichTextDocument.schemaVersion) {
        self.schemaVersion = schemaVersion
        self.text = text
        self.paragraphs = paragraphs
    }

    /// Empty document.
    public static let empty = RichTextDocument(text: "", paragraphs: [])

    /// A plain-text-only document with a single body paragraph (no marks).
    /// Useful for testing and for fresh rich-text blocks.
    public static func plain(_ text: String) -> RichTextDocument {
        let scalarCount = text.unicodeScalars.count
        guard scalarCount > 0 else {
            return .empty
        }
        let paragraph = RichTextParagraph(
            startScalar: 0,
            endScalar: scalarCount,
            style: .body,
            runs: []
        )
        return RichTextDocument(text: text, paragraphs: [paragraph])
    }

    /// Convenience: the document's plain-text representation (NFC). Same as
    /// `text` — provided for clarity at call sites.
    public var plainText: String { text }
}

// MARK: - NFC normalization
//
// Per research.md R16: persisted text is normalized to NFC at the canonical
// boundary. Use Foundation's `String` (which is composed-character-based but
// can be normalized via `.precomposedStringWithCompatibilityMapping` for
// NFKD or `.precomposedStringWithCanonicalMapping` for NFC).

public enum UnicodeNormalization {
    /// Normalize the given string to NFC (canonical decomposition followed
    /// by canonical composition). The canonical boundary uses NFC.
    public static func nfc(_ string: String) -> String {
        string.precomposedStringWithCanonicalMapping
    }
}
