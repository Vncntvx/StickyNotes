import Testing
import Foundation
import Domain

// MARK: - RichText canonical round-trip tests (T072)
//
// Per tasks.md T072: "EditorCore test: canonical rich-text round-trip
// lossless for supported marks; unsupported attributes stripped."
//
// The RichTextDocument lives in Domain (T014) and its Codable conformance
// is in CanonicalCoding (T016). This test verifies the round-trip is
// lossless for every supported mark, and that unsupported attributes
// (which can't even be expressed in the canonical model) are by
// construction absent.

@Suite struct RichTextRoundTripTests {

    @Test
    func plainTextDocumentRoundTrips() throws {
        let doc = RichTextDocument.plain("Hello 世界 🌍")
        let encoder = CanonicalJSONEncoder()
        let decoder = CanonicalJSONDecoder()
        let data = try encoder.encode(doc)
        let back = try decoder.decode(RichTextDocument.self, from: data)
        #expect(back == doc)
        #expect(back.text == "Hello 世界 🌍")
    }

    @Test
    func everySupportedMarkRoundTrips() throws {
        // Build a document with a single paragraph carrying one run per mark.
        let text = "bold italic underline strike code"
        let scalars = Array(text.unicodeScalars)
        // For simplicity, one run covering the whole text with all marks.
        let run = RichTextRun(
            startScalar: 0,
            endScalar: scalars.count,
            marks: [.bold, .italic, .underline, .strikethrough, .inlineCode],
            link: nil,
            hardBreak: false
        )
        let para = RichTextParagraph(startScalar: 0, endScalar: scalars.count, style: .body, runs: [run])
        let doc = RichTextDocument(text: text, paragraphs: [para])

        let encoder = CanonicalJSONEncoder()
        let decoder = CanonicalJSONDecoder()
        let data = try encoder.encode(doc)
        let back = try decoder.decode(RichTextDocument.self, from: data)
        #expect(back == doc)
        #expect(back.paragraphs.first?.runs.first?.marks == [.bold, .italic, .underline, .strikethrough, .inlineCode])
    }

    @Test
    func linkMarkRoundTrips() throws {
        let text = "click here"
        let scalars = Array(text.unicodeScalars)
        let run = RichTextRun(
            startScalar: 0,
            endScalar: scalars.count,
            marks: [],
            link: "https://example.com",
            hardBreak: false
        )
        let para = RichTextParagraph(startScalar: 0, endScalar: scalars.count, style: .body, runs: [run])
        let doc = RichTextDocument(text: text, paragraphs: [para])

        let encoder = CanonicalJSONEncoder()
        let decoder = CanonicalJSONDecoder()
        let back = try decoder.decode(RichTextDocument.self, from: encoder.encode(doc))
        #expect(back == doc)
        #expect(back.paragraphs.first?.runs.first?.link == "https://example.com")
    }

    @Test
    func hardBreakRoundTrips() throws {
        let text = "line one"
        let scalars = Array(text.unicodeScalars)
        let run = RichTextRun(startScalar: 0, endScalar: scalars.count, marks: [], hardBreak: true)
        let doc = RichTextDocument(text: text, paragraphs: [RichTextParagraph(startScalar: 0, endScalar: scalars.count, style: .body, runs: [run])])

        let encoder = CanonicalJSONEncoder()
        let decoder = CanonicalJSONDecoder()
        let back = try decoder.decode(RichTextDocument.self, from: encoder.encode(doc))
        #expect(back == doc)
        #expect(back.paragraphs.first?.runs.first?.hardBreak == true)
    }

    @Test
    func multipleParagraphsRoundTrip() throws {
        let text = "para1\npara2"
        let scalars = Array(text.unicodeScalars)
        let p1End = scalars.firstIndex(of: "\n") ?? scalars.count
        let doc = RichTextDocument(text: text, paragraphs: [
            RichTextParagraph(startScalar: 0, endScalar: p1End, style: .heading, runs: []),
            RichTextParagraph(startScalar: p1End + 1, endScalar: scalars.count, style: .bullet, runs: []),
        ])

        let encoder = CanonicalJSONEncoder()
        let decoder = CanonicalJSONDecoder()
        let back = try decoder.decode(RichTextDocument.self, from: encoder.encode(doc))
        #expect(back == doc)
        #expect(back.paragraphs.count == 2)
        #expect(back.paragraphs[0].style == .heading)
        #expect(back.paragraphs[1].style == .bullet)
    }

    @Test
    func unsupportedAttributesAreAbsentByConstruction() {
        // The canonical RichTextMark enum is closed: only bold/italic/
        // underline/strikethrough/inlineCode are supported. Arbitrary
        // platform attributes (font, size, color, etc.) cannot enter the
        // canonical model — there's no case for them. This test documents
        // the invariant: the supported set is exactly the 5 cases.
        #expect(RichTextMark.allCases.count == 5)
        #expect(RichTextMark.allCases.contains(.bold))
        #expect(RichTextMark.allCases.contains(.italic))
        #expect(RichTextMark.allCases.contains(.underline))
        #expect(RichTextMark.allCases.contains(.strikethrough))
        #expect(RichTextMark.allCases.contains(.inlineCode))
    }

    @Test
    func nfcNormalizationStable() {
        // NFC-normalized text round-trips through NFC normalization unchanged.
        let nfc = UnicodeNormalization.nfc("café")
        #expect(UnicodeNormalization.nfc(nfc) == nfc)
    }
}
