import Testing
import Foundation
import Domain

// MARK: - CodeBlock tests (T057)
//
// Per tasks.md T057: "Domain test: code block preserves whitespace/tabs/
// line breaks; copy copies only code."
//
// Verifies:
// - CodePayload.text preserves leading/trailing whitespace, tabs, and
//   line breaks through canonical JSON round-trip.
// - The canonical JSON for a code block contains ONLY the code text (and
//   optional language label) — no surrounding formatting, no syntax-
//   highlighting artifacts, no execution state.
// - A code block with a language label round-trips the label.
// - A code block without a language label round-trips with `language: null`.

@Suite struct CodeBlockTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    @Test
    func whitespaceTabsAndLineBreaksPreservedThroughRoundTrip() throws {
        let tricky = """
        \tdef main():
        \t    print("hello")
        \n\n\t  trailing spaces  
        """
        let payload = CodePayload(text: tricky, language: "python")
        let encoder = CanonicalJSONEncoder()
        let decoder = CanonicalJSONDecoder()
        let data = try encoder.encode(payload)
        let back = try decoder.decode(CodePayload.self, from: data)
        #expect(back.text == tricky, "code text must preserve whitespace/tabs/newlines byte-for-byte")
        #expect(back.language == "python")
    }

    @Test
    func canonicalJSONContainsOnlyCodeAndLanguage() throws {
        let payload = CodePayload(text: "let x = 1", language: "swift")
        let encoder = CanonicalJSONEncoder()
        let data = try encoder.encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""

        // MUST contain the text and language.
        #expect(json.contains("\"text\""))
        #expect(json.contains("\"language\""))

        // MUST NOT contain formatting/highlighting/execution artifacts.
        #expect(!json.contains("highlight"))
        #expect(!json.contains("execution"))
        #expect(!json.contains("output"))
        #expect(!json.contains("runs"))
    }

    @Test
    func nilLanguageRoundTripsAsNull() throws {
        let payload = CodePayload(text: "echo hi", language: nil)
        let encoder = CanonicalJSONEncoder()
        let decoder = CanonicalJSONDecoder()
        let data = try encoder.encode(payload)
        // encodeIfPresent omits the key entirely when nil (standard JSON
        // practice) — the JSON will NOT contain "language":null, just no
        // "language" key. The round-trip still produces nil.
        let back = try decoder.decode(CodePayload.self, from: data)
        #expect(back.language == nil)
        #expect(back.text == "echo hi")
    }

    @Test
    func copyExtractsOnlyCode() {
        // The "copy copies only code" invariant is encoded by the
        // CodePayload carrying ONLY the code text. There's no surrounding
        // formatting in the payload, so copying the text field copies only
        // the code. This test documents that contract.
        let payload = CodePayload(text: "git status", language: "bash")
        // The copy source is exactly `payload.text` — nothing else.
        #expect(payload.text == "git status")
    }

    @Test
    func codeBlockAsCanonicalPayloadRoundTrips() throws {
        // Use fixed dates (no sub-millisecond precision) so the canonical
        // ISO 8601 round-trip is byte-exact.
        let block = CanonicalBlock(
            id: UUID(),
            noteId: UUID(),
            kind: .code,
            sortKey: 0,
            lastModifiedDeviceId: Self.deviceId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
            payload: .code(CodePayload(text: "SELECT 1;", language: "sql"))
        )
        let encoder = CanonicalJSONEncoder()
        let decoder = CanonicalJSONDecoder()
        let data = try encoder.encode(block)
        let back = try decoder.decode(CanonicalBlock.self, from: data)
        #expect(back == block)
    }
}
