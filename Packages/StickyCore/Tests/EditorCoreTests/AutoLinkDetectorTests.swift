import Testing
import Foundation
import Domain
@testable import EditorCore

// MARK: - Auto-link detection tests (T148, FR-050)
//
// Per tasks.md T148: "auto-link detection recognizes web URLs, email
// addresses, telephone numbers; emits canonical rich-text `link` mark; no
// false positives inside code blocks per FR-050".

@Suite struct AutoLinkDetectorTests {

    @Test
    func detectsHTTPSURLs() {
        let text = "Visit https://example.com/docs now"
        let links = AutoLinkDetector.detectLinks(in: text, insideCodeBlock: false)
        #expect(links.count == 1)
        #expect(links[0].target == "https://example.com/docs")
        #expect(text[text.index(text.startIndex, offsetBy: links[0].range.lowerBound)...] .hasPrefix("https"))
    }

    @Test
    func detectsHTTPURLs() {
        let text = "http://example.org works"
        let links = AutoLinkDetector.detectLinks(in: text, insideCodeBlock: false)
        #expect(links.count == 1)
        #expect(links[0].target == "http://example.org")
    }

    @Test
    func detectsWwwUrlsWithoutScheme() {
        let text = "see www.example.com/page for details"
        let links = AutoLinkDetector.detectLinks(in: text, insideCodeBlock: false)
        #expect(links.count == 1)
        // NSDataDetector normalizes scheme-less www to http:// (R3.5).
        #expect(links[0].target == "http://www.example.com/page")
    }

    @Test
    func detectsEmailAddresses() {
        let text = "mail me at user@example.com please"
        let links = AutoLinkDetector.detectLinks(in: text, insideCodeBlock: false)
        #expect(links.count == 1)
        #expect(links[0].target == "mailto:user@example.com")
    }

    @Test
    func detectsTelephoneNumbers() {
        let text = "call +1 (555) 123-4567 today"
        let links = AutoLinkDetector.detectLinks(in: text, insideCodeBlock: false)
        #expect(links.count == 1)
        // International numbers normalize to E.164 (R3.5).
        #expect(links[0].target == "tel:+15551234567")
    }

    @Test
    func detectsUSPhoneNumber() {
        let text = "555-123-4567"
        let links = AutoLinkDetector.detectLinks(in: text, insideCodeBlock: false)
        #expect(links.count == 1)
        // LOCAL numbers keep their formatting — no invented "+" prefix
        // (R3.5; the old scanner produced meaningless tel:+5551234567).
        #expect(links[0].target == "tel:555-123-4567")
    }

    @Test
    func noFalsePositivesInsideCodeBlocks() {
        let text = "const url = 'https://example.com'; // user@example.com 555-123-4567"
        let links = AutoLinkDetector.detectLinks(in: text, insideCodeBlock: true)
        #expect(links.isEmpty, "code blocks produce no link detection (FR-050)")
    }

    @Test
    func emitsLinkMarkOnConversion() {
        // The App layer feeds DetectedLink ranges into RichTextAdapter's
        // canonical runs as the `link` mark. Assert the adapter carries the
        // target through.
        let text = "see https://example.com"
        let links = AutoLinkDetector.detectLinks(in: text, insideCodeBlock: false)
        guard let link = links.first else {
            Issue.record("expected a link")
            return
        }
        let runs = RichTextAdapter.runs(for: [], range: link.range, link: link.target)
        #expect(runs.count == 1)
        #expect(runs[0].link == "https://example.com")
    }

    @Test
    func noFalsePositiveOnPlainText() {
        let text = "This is plain text with 42 numbers and dots.and.words"
        let links = AutoLinkDetector.detectLinks(in: text, insideCodeBlock: false)
        #expect(links.isEmpty)
    }
}
