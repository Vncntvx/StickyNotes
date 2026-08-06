import Testing
import Foundation
@testable import Domain

// MARK: - Rich-text document tests (T014)
//
// Verifies the canonical rich-text model per contracts/rich-text.schema.json:
// - NFC text + scalar-offset runs.
// - Round-trip lossless for supported marks (bold/italic/underline/strike/
//   inlineCode), link, hardBreak.
// - Plain-text-only document constructor.
// - Empty document.
//
// Constitution IV (explicit, durable, versioned data); research.md R16
// (Unicode normalization and index stability).

@Suite struct RichTextDocumentTests {

    @Test
    func emptyDocumentHasNoParagraphs() {
        #expect(RichTextDocument.empty.text == "")
        #expect(RichTextDocument.empty.paragraphs.isEmpty)
    }

    @Test
    func plainConstructorProducesSingleBodyParagraph() {
        let doc = RichTextDocument.plain("Hello")
        #expect(doc.text == "Hello")
        #expect(doc.paragraphs.count == 1)
        #expect(doc.paragraphs[0].style == .body)
        #expect(doc.paragraphs[0].startScalar == 0)
        #expect(doc.paragraphs[0].endScalar == 5)
        #expect(doc.paragraphs[0].runs.isEmpty, "Plain document has no marks")
    }

    @Test
    func plainConstructorHandlesCJKAndEmojiScalars() {
        // "世界🌍" — 3 scalars (世, 界, 🌍). The emoji is a single scalar
        // outside the BMP (U+1F30D), so scalar count != Character count
        // if a string were measured in graphemes.
        let doc = RichTextDocument.plain("世界🌍")
        #expect(doc.text == "世界🌍")
        #expect(doc.paragraphs[0].endScalar == 3, "Scalar count must be 3, not grapheme count")
    }

    @Test
    func roundTripPreservesMarksAndLink() throws {
        let encoder = CanonicalJSONEncoder()
        let decoder = CanonicalJSONDecoder()

        let doc = RichTextDocument(
            text: "Hello world",
            paragraphs: [
                RichTextParagraph(
                    startScalar: 0,
                    endScalar: 11,
                    style: .body,
                    runs: [
                        RichTextRun(
                            startScalar: 0,
                            endScalar: 5,
                            marks: [.bold, .italic],
                            link: nil,
                            hardBreak: false
                        ),
                        RichTextRun(
                            startScalar: 6,
                            endScalar: 11,
                            marks: [.inlineCode],
                            link: "https://example.com",
                            hardBreak: true
                        ),
                    ]
                )
            ]
        )

        let data = try encoder.encode(doc)
        let decoded = try decoder.decode(RichTextDocument.self, from: data)

        #expect(decoded == doc)
        #expect(decoded.paragraphs[0].runs[0].marks == [.bold, .italic])
        #expect(decoded.paragraphs[0].runs[1].link == "https://example.com")
        #expect(decoded.paragraphs[0].runs[1].hardBreak == true)
    }

    @Test
    func roundTripPreservesParagraphStyles() throws {
        let encoder = CanonicalJSONEncoder()
        let decoder = CanonicalJSONDecoder()

        let doc = RichTextDocument(
            text: "Heading\n• bullet\nbody",
            paragraphs: [
                RichTextParagraph(startScalar: 0, endScalar: 7, style: .heading, runs: []),
                RichTextParagraph(startScalar: 8, endScalar: 16, style: .bullet, runs: []),
                RichTextParagraph(startScalar: 17, endScalar: 21, style: .body, runs: []),
            ]
        )

        let data = try encoder.encode(doc)
        let decoded = try decoder.decode(RichTextDocument.self, from: data)

        #expect(decoded == doc)
        #expect(decoded.paragraphs.map(\.style) == [.heading, .bullet, .body])
    }

    @Test
    func nfcNormalizationCollapsesComposedForms() {
        // "é" can be a single precomposed scalar (U+00E9) or a decomposed
        // pair (U+0065 + U+0301). NFC normalizes to the precomposed form.
        let precomposed: String = "é"           // U+00E9
        let decomposed: String = "e\u{0301}"    // U+0065 + U+0301

        let nfcPrecomposed = UnicodeNormalization.nfc(precomposed)
        let nfcDecomposed = UnicodeNormalization.nfc(decomposed)

        #expect(nfcPrecomposed == nfcDecomposed, "NFC must collapse composed/decomposed forms")
        #expect(nfcPrecomposed.unicodeScalars.count == 1, "Precomposed é is one scalar in NFC")
    }

    @Test
    func schemaVersionIsOne() {
        #expect(RichTextDocument.schemaVersion == 1)
        #expect(RichTextDocument.empty.schemaVersion == 1)
    }

    @Test
    func unsupportedMarksAreNotInSupportedSet() {
        // The supported mark set is closed: bold, italic, underline,
        // strikethrough, inlineCode. Nothing else can appear in canonical
        // rich text (constitution V — only supported formatting persists).
        let allMarks: Set<RichTextMark> = [.bold, .italic, .underline, .strikethrough, .inlineCode]
        #expect(RichTextMark.allCases.count == 5)
        #expect(Set(RichTextMark.allCases) == allMarks)
    }
}
