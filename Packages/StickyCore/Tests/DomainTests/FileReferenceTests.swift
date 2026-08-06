import Testing
import Foundation
import Domain

// MARK: - FileReference + FileLocator tests (T058)
//
// Per tasks.md T058: "Domain test: FileReference syncs only generic
// metadata; FileLocator bookmark/paths never in canonical JSON."
//
// Constitution IX: file references are references (not cloud attachments).
// Only generic metadata syncs; bookmark bytes + absolute paths NEVER appear
// in canonical JSON. This test encodes the invariant at the canonical
// boundary.

@Suite struct FileReferenceTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    // MARK: - FileReferencePayload (synced) — canonical JSON contains
    //         generic metadata only, NO bookmark bytes, NO paths.

    @Test
    func fileReferencePayloadEncodesGenericMetadataOnly() throws {
        let payload = FileReferencePayload(
            displayName: "report.pdf",
            contentType: "com.adobe.pdf",
            approximateSize: 248_320,
            originDeviceId: Self.deviceId,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            caption: "Q3 report"
        )
        let encoder = CanonicalJSONEncoder()
        let data = try encoder.encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""

        // MUST contain generic metadata.
        #expect(json.contains("\"displayName\""))
        #expect(json.contains("\"contentType\""))
        #expect(json.contains("\"approximateSize\""))
        #expect(json.contains("\"originDeviceId\""))
        #expect(json.contains("\"addedAt\""))
        #expect(json.contains("\"caption\""))

        // MUST NOT contain bookmark bytes, absolute paths, or storage paths.
        #expect(!json.contains("bookmark"))
        #expect(!json.contains("path"))
        #expect(!json.contains("storagePath"))
        #expect(!json.contains("lastResolvedPath"))
    }

    @Test
    func fileReferencePayloadRoundTripsLossless() throws {
        let payload = FileReferencePayload(
            displayName: "schema.sql",
            contentType: "public.sql",
            approximateSize: nil,  // test nil round-trip
            originDeviceId: Self.deviceId,
            addedAt: Date(timeIntervalSince1970: 1_700_000_500),
            caption: nil
        )
        let encoder = CanonicalJSONEncoder()
        let decoder = CanonicalJSONDecoder()
        let data = try encoder.encode(payload)
        let back = try decoder.decode(FileReferencePayload.self, from: data)
        #expect(back == payload)
    }

    // MARK: - FileLocator (device-local) — bookmark bytes + paths

    @Test
    func fileLocatorCarriesBookmarkAndPath() {
        let locator = FileLocator(
            blockId: UUID(),
            bookmarkData: Data([0x00, 0x01, 0x02, 0x03]),
            lastResolvedPath: "/Users/me/Documents/report.pdf",
            availabilityStatus: .available,
            stale: false,
            verifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(!locator.bookmarkData.isEmpty)
        #expect(locator.lastResolvedPath.hasPrefix("/Users/"))
        #expect(locator.availabilityStatus == .available)
    }

    @Test
    func fileLocatorIsNotPartOfCanonicalBlockPayload() throws {
        // The CanonicalBlockPayload.fileReference case carries
        // FileReferencePayload (generic metadata) ONLY. The locator is a
        // separate device-local row. This test encodes a fileReference
        // block and asserts the locator fields are absent from the JSON.
        let blockId = UUID()
        let payload = CanonicalBlockPayload.fileReference(FileReferencePayload(
            displayName: "notes.txt",
            contentType: "public.plain-text",
            originDeviceId: Self.deviceId,
            addedAt: Date()
        ))
        let block = CanonicalBlock(
            id: blockId,
            noteId: UUID(),
            kind: .fileRef,
            sortKey: 0,
            lastModifiedDeviceId: Self.deviceId,
            payload: payload
        )
        let encoder = CanonicalJSONEncoder()
        let data = try encoder.encode(block)
        let json = String(data: data, encoding: .utf8) ?? ""

        // The canonical block JSON must NOT contain locator fields.
        #expect(!json.contains("bookmarkData"))
        #expect(!json.contains("lastResolvedPath"))
        #expect(!json.contains("availabilityStatus"))
        #expect(!json.contains("verifiedAt"))
        #expect(!json.contains("stale"))

        // And it MUST contain the generic metadata.
        #expect(json.contains("displayName"))
        #expect(json.contains("contentType"))
    }

    // MARK: - File availability state machine (data-model.md §File reference availability)

    @Test
    func availabilityStatesCoverLifecycle() {
        // available → stale → missing → relinked → available
        #expect(FileAvailability.allCases.count == 4)
        #expect(FileAvailability.allCases.contains(.available))
        #expect(FileAvailability.allCases.contains(.stale))
        #expect(FileAvailability.allCases.contains(.missing))
        #expect(FileAvailability.allCases.contains(.relinked))
    }
}
