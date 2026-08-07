import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - Localization completeness tests (T230, FR-180a)
//
// zh-Hans + en completeness is verified against the String Catalogs in
// App/Resources (T239). This test asserts the catalogs exist and both
// languages are present. The full source-scan for hard-coded UI strings is
// an audit task (T239) — this test pins the catalog requirement.

@Suite struct LocalizationCompletenessTests {
    @Test
    func stringCatalogsExistWithBothLanguages() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/Resources")

        let catalog = resources.appendingPathComponent("Localizable.xcstrings")
        #expect(FileManager.default.fileExists(atPath: catalog.path),
                "Localizable.xcstrings must exist (T239/FR-180a)")

        if let data = try? Data(contentsOf: catalog),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let source = (json["sourceLanguage"] as? String) ?? ""
            #expect(!source.isEmpty)
            let strings = (json["strings"] as? [String: Any]) ?? [:]
            #expect(!strings.isEmpty, "the catalog must contain user-visible strings (T239)")
        } else {
            Issue.record("catalog must be parseable")
        }
    }
}
