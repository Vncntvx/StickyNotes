import Testing
import Foundation
@testable import Domain

// MARK: - CanonicalNote round-trip JSON tests (T028)
//
// Per tasks.md T028: "Domain test: canonical Note round-trip JSON lossless".
// Verifies that a CanonicalNote with all six block kinds survives a
// CanonicalJSONEncoder → CanonicalJSONDecoder round-trip byte-for-byte
// (stable keys, ISO 8601 UTC, UUID strings, explicit schemaVersion).
//
// Constitution IV (explicit, durable, versioned data) — the canonical form
// is what gets persisted, exported, and encrypted for sync. Round-trip
// losslessness is a non-negotiable invariant.

@Suite struct CanonicalNoteTests {

    // MARK: - Helpers

    private func roundTripJSON(_ note: CanonicalNote) throws -> CanonicalNote {
        let encoder = CanonicalJSONEncoder()
        let decoder = CanonicalJSONDecoder()
        let data = try encoder.encode(note)
        return try decoder.decode(CanonicalNote.self, from: data)
    }

    private static func makeNote() -> CanonicalNote {
        let deviceId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let noteId = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let modifiedAt = Date(timeIntervalSince1970: 1_700_000_100)

        let blocks: [CanonicalBlock] = [
            // Rich-text block
            CanonicalBlock(
                id: UUID(uuidString: "b0000000-0000-4000-8000-000000000001")!,
                noteId: noteId,
                kind: .richText,
                sortKey: 0,
                parentVersionId: nil,
                lastModifiedDeviceId: deviceId,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                payload: .richText(RichTextDocument.plain("Hello 世界 🌍"))
            ),
            // Todo block
            CanonicalBlock(
                id: UUID(uuidString: "b0000000-0000-4000-8000-000000000002")!,
                noteId: noteId,
                kind: .todo,
                sortKey: 1024,
                parentVersionId: nil,
                lastModifiedDeviceId: deviceId,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                payload: .todo(TodoPayload(
                    todoId: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
                    richText: RichTextDocument.plain("Buy groceries")
                ))
            ),
            // Code block
            CanonicalBlock(
                id: UUID(uuidString: "b0000000-0000-4000-8000-000000000003")!,
                noteId: noteId,
                kind: .code,
                sortKey: 2048,
                parentVersionId: nil,
                lastModifiedDeviceId: deviceId,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                payload: .code(CodePayload(text: "let x = 1\nprint(x)", language: "swift"))
            ),
            // File-reference block
            CanonicalBlock(
                id: UUID(uuidString: "b0000000-0000-4000-8000-000000000004")!,
                noteId: noteId,
                kind: .fileRef,
                sortKey: 3072,
                parentVersionId: nil,
                lastModifiedDeviceId: deviceId,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                payload: .fileReference(FileReferencePayload(
                    displayName: "report.pdf",
                    contentType: "com.adobe.pdf",
                    approximateSize: 248_320,
                    originDeviceId: deviceId,
                    addedAt: createdAt,
                    caption: "Q3 report"
                ))
            ),
            // Image block
            CanonicalBlock(
                id: UUID(uuidString: "b0000000-0000-4000-8000-000000000005")!,
                noteId: noteId,
                kind: .image,
                sortKey: 4096,
                parentVersionId: nil,
                lastModifiedDeviceId: deviceId,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                payload: .image(EmbeddedImagePayload(
                    originalAssetId: UUID(uuidString: "a0000000-0000-4000-8000-000000000001")!,
                    thumbnailAssetId: UUID(uuidString: "a0000000-0000-4000-8000-000000000002")!,
                    caption: nil
                ))
            ),
            // Screenshot block
            CanonicalBlock(
                id: UUID(uuidString: "b0000000-0000-4000-8000-000000000006")!,
                noteId: noteId,
                kind: .screenshot,
                sortKey: 5120,
                parentVersionId: nil,
                lastModifiedDeviceId: deviceId,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                payload: .screenshot(ScreenshotPayload(
                    originalAssetId: UUID(uuidString: "a0000000-0000-4000-8000-000000000003")!,
                    thumbnailAssetId: UUID(uuidString: "a0000000-0000-4000-8000-000000000004")!,
                    appIconAssetId: nil,
                    applicationName: "Safari",
                    windowTitle: "Apple",
                    caption: nil,
                    capturedAt: modifiedAt,
                    isCover: true
                ))
            ),
        ]

        return CanonicalNote(
            id: noteId,
            title: "测试 Note — 世界",
            colorKey: .custom,
            customColor: "#FF8800",
            transparency: 0.15,
            textSize: 18,
            alwaysOnTop: true,
            widgetEligible: true,
            coverScreenshotBlockId: blocks[5].id,
            manualSortKey: 1024,
            lifecycleState: .active,
            trashedAt: nil,
            conflictOriginNoteId: nil,
            conflictLabel: nil,
            versionId: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
            parentVersionId: nil,
            lastModifiedDeviceId: deviceId,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            blocks: blocks
        )
    }

    // MARK: - Tests

    @Test
    func roundTripPreservesAllFields() throws {
        let original = Self.makeNote()
        let decoded = try roundTripJSON(original)

        #expect(decoded == original, "CanonicalNote round-trip must be lossless")
        #expect(decoded.schemaVersion == CanonicalNote.schemaVersion)
        #expect(decoded.blocks.count == 6)
        #expect(decoded.blocks.map(\.kind) == [.richText, .todo, .code, .fileRef, .image, .screenshot])
    }

    @Test
    func roundTripPreservesEmojiAndCJKText() throws {
        let original = Self.makeNote()
        let decoded = try roundTripJSON(original)

        let richTextBlock = decoded.blocks[0]
        guard case .richText(let doc) = richTextBlock.payload else {
            Issue.record("Expected richText payload"); return
        }
        #expect(doc.text == "Hello 世界 🌍")
        #expect(decoded.title == "测试 Note — 世界")
    }

    @Test
    func roundTripPreservesAllPayloadKinds() throws {
        let original = Self.makeNote()
        let decoded = try roundTripJSON(original)

        // Verify each payload kind survives with its associated data intact.
        guard case .richText(let rt) = decoded.blocks[0].payload else {
            Issue.record("richText payload lost"); return
        }
        #expect(rt.plainText == "Hello 世界 🌍")

        guard case .todo(let todo) = decoded.blocks[1].payload else {
            Issue.record("todo payload lost"); return
        }
        #expect(todo.richText.plainText == "Buy groceries")

        guard case .code(let code) = decoded.blocks[2].payload else {
            Issue.record("code payload lost"); return
        }
        #expect(code.text == "let x = 1\nprint(x)")
        #expect(code.language == "swift")

        guard case .fileReference(let fileRef) = decoded.blocks[3].payload else {
            Issue.record("fileReference payload lost"); return
        }
        #expect(fileRef.displayName == "report.pdf")
        #expect(fileRef.contentType == "com.adobe.pdf")
        #expect(fileRef.approximateSize == 248_320)
        #expect(fileRef.caption == "Q3 report")

        guard case .image(let img) = decoded.blocks[4].payload else {
            Issue.record("image payload lost"); return
        }
        #expect(img.originalAssetId == UUID(uuidString: "a0000000-0000-4000-8000-000000000001")!)

        guard case .screenshot(let shot) = decoded.blocks[5].payload else {
            Issue.record("screenshot payload lost"); return
        }
        #expect(shot.applicationName == "Safari")
        #expect(shot.windowTitle == "Apple")
        #expect(shot.isCover == true)
    }

    @Test
    func encodingIsDeterministic() throws {
        // Same input → same output bytes. Required for SHA-256 content hashing
        // (AssetStore dedup) and for stable diffs.
        let encoder = CanonicalJSONEncoder()
        let note = Self.makeNote()

        let data1 = try encoder.encode(note)
        let data2 = try encoder.encode(note)

        #expect(data1 == data2, "Encoding must be deterministic for content hashing")
    }

    @Test
    func schemaVersionIsExplicit() throws {
        let encoder = CanonicalJSONEncoder()
        let note = Self.makeNote()
        let data = try encoder.encode(note)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Invalid JSON"); return
        }
        #expect(json["schemaVersion"] as? Int == 1)
    }

    @Test
    func datesAreISO8601UTCWithZSuffix() throws {
        let encoder = CanonicalJSONEncoder()
        let note = Self.makeNote()
        let data = try encoder.encode(note)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Invalid JSON"); return
        }
        let createdAt = json["createdAt"] as? String
        #expect(createdAt?.hasSuffix("Z") == true, "createdAt must end with Z (UTC): \(createdAt ?? "nil")")
        // 1_700_000_000 = 2023-11-14T22:13:20.000Z
        #expect(createdAt?.hasPrefix("2023-11-14") == true)
    }
}
