import Testing
import Foundation
import Domain

// MARK: - Note export/import round-trip tests (T224, FR-031a)
//
// Per tasks.md T224: "Domain/Persistence test: note JSON export/import
// round-trip per FR-031a — export a note containing every block kind (rich
// text with all supported attributes, todos incl. nesting/state/order, code
// block, file reference, embedded image, screenshot) → import the JSON →
// assert byte-level semantic equality of text, rich-text attributes, todo
// identity/text/state/nesting/order, code text, image/screenshot asset
// payloads, and appearance (color, transparency, text size, Always-on-Top);
// assert file-reference blocks import with generic metadata only (display
// name, content type, size, origin device, added date — NEVER bookmark bytes
// or absolute paths per FR-105); assert importing an unsupported schema
// version or corrupted envelope fails closed with NO partial note created;
// assert the exported document validates against
// contracts/note-document.schema.json".

@Suite struct NoteExportImportRoundTripTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    private func makeFullNote() -> (Note, [Block]) {
        let note = Note(
            title: "Shopping",
            colorKey: .pink,
            transparency: 0.85,
            textSize: 17,
            alwaysOnTop: true,
            lastModifiedDeviceId: Self.deviceId
        )
        let richDoc = RichTextDocument(
            text: "Buy milk **and** eggs",
            paragraphs: [RichTextParagraph(
                startScalar: 0,
                endScalar: 21,
                style: .body,
                runs: [
                    RichTextRun(startScalar: 9, endScalar: 14, marks: [.bold]),
                ]
            )]
        )
        let todoDoc = RichTextDocument.plain("Subtask")
        let blocks = [
            Block(
                id: UUID(uuidString: "b0000000-0000-4000-8000-000000000001")!,
                noteId: note.id,
                kind: .richText,
                sortKey: 0,
                payload: .richText(richDoc),
                lastModifiedDeviceId: Self.deviceId
            ),
            Block(
                id: UUID(uuidString: "b0000000-0000-4000-8000-000000000002")!,
                noteId: note.id,
                kind: .todo,
                sortKey: 1024,
                payload: .todo(TodoPayload(todoId: UUID(uuidString: "c0000000-0000-4000-8000-000000000001")!, richText: todoDoc)),
                lastModifiedDeviceId: Self.deviceId
            ),
            Block(
                id: UUID(uuidString: "b0000000-0000-4000-8000-000000000003")!,
                noteId: note.id,
                kind: .code,
                sortKey: 2048,
                payload: .code(CodePayload(text: "let x = 1\n\ty = 2", language: "swift")),
                lastModifiedDeviceId: Self.deviceId
            ),
            Block(
                id: UUID(uuidString: "b0000000-0000-4000-8000-000000000004")!,
                noteId: note.id,
                kind: .fileRef,
                sortKey: 3072,
                payload: .fileReference(FileReferencePayload(
                    displayName: "report.pdf",
                    contentType: "com.adobe.pdf",
                    approximateSize: 248320,
                    originDeviceId: Self.deviceId,
                    addedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )),
                lastModifiedDeviceId: Self.deviceId
            ),
            Block(
                id: UUID(uuidString: "b0000000-0000-4000-8000-000000000005")!,
                noteId: note.id,
                kind: .image,
                sortKey: 4096,
                payload: .image(EmbeddedImagePayload(
                    originalAssetId: UUID(uuidString: "a0000000-0000-4000-8000-000000000001")!,
                    thumbnailAssetId: UUID(uuidString: "a0000000-0000-4000-8000-000000000002")!,
                    caption: "pasted logo"
                )),
                lastModifiedDeviceId: Self.deviceId
            ),
            Block(
                id: UUID(uuidString: "b0000000-0000-4000-8000-000000000006")!,
                noteId: note.id,
                kind: .screenshot,
                sortKey: 5120,
                payload: .screenshot(ScreenshotPayload(
                    originalAssetId: UUID(uuidString: "a0000000-0000-4000-8000-000000000003")!,
                    thumbnailAssetId: UUID(uuidString: "a0000000-0000-4000-8000-000000000004")!,
                    applicationName: "Finder",
                    windowTitle: "Documents",
                    caption: "capture",
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_100),
                    isCover: true
                )),
                lastModifiedDeviceId: Self.deviceId
            ),
        ]
        return (note, blocks)
    }

    @Test
    func fullRoundTripPreservesAllBlocksAndAppearance() throws {
        let (note, blocks) = makeFullNote()
        let assetBytes: [UUID: Data] = [
            UUID(uuidString: "a0000000-0000-4000-8000-000000000001")!: Data([0x89, 0x50, 0x4E, 0x47]),
            UUID(uuidString: "a0000000-0000-4000-8000-000000000003")!: Data([0xFF, 0xD8, 0xFF]),
        ]

        let document = try NoteDocumentSerializer.exportDocument(note: note, blocks: blocks, assetBytes: assetBytes)
        let data = try NoteDocumentSerializer.encodeDocument(document)
        let sidecar = try NoteDocumentSerializer.encodeAssetSidecar(assetBytes)

        let imported = try NoteDocumentSerializer.decodeDocument(from: data)
        let importedBytes = try NoteDocumentSerializer.decodeAssetSidecar(from: sidecar)

        // Note-level appearance equality (FR-031a).
        #expect(imported.title == note.title)
        #expect(imported.colorKey == note.colorKey)
        #expect(imported.customColor == note.customColor)
        #expect(imported.transparency == note.transparency)
        #expect(imported.textSize == note.textSize)
        #expect(imported.alwaysOnTop == note.alwaysOnTop)
        #expect(imported.manualSortKey == note.manualSortKey)
        #expect(imported.blocks.count == blocks.count)

        // Byte-level semantic equality of text + attributes.
        for (index, original) in blocks.sorted(by: { $0.sortKey < $1.sortKey }).enumerated() {
            let roundTripped = imported.blocks[index]
            #expect(roundTripped.kind == original.kind)
            #expect(roundTripped.sortKey == original.sortKey)
            switch original.payload {
            case .richText(let doc):
                guard case .richText(let rt) = roundTripped.payload else {
                    Issue.record("expected richText payload"); continue
                }
                #expect(rt.text == doc.text)
                #expect(rt.paragraphs == doc.paragraphs)
            case .todo(let todo):
                guard case .todo(let rt) = roundTripped.payload else {
                    Issue.record("expected todo payload"); continue
                }
                #expect(rt.todoId == todo.todoId)
                #expect(rt.richText.text == todo.richText.text)
                #expect(rt.richText.paragraphs == todo.richText.paragraphs)
            case .code(let code):
                guard case .code(let rt) = roundTripped.payload else {
                    Issue.record("expected code payload"); continue
                }
                #expect(rt.text == code.text)
                #expect(rt.language == code.language)
            case .fileReference(let ref):
                guard case .fileReference(let rt) = roundTripped.payload else {
                    Issue.record("expected fileReference payload"); continue
                }
                #expect(rt.displayName == ref.displayName)
                #expect(rt.contentType == ref.contentType)
                #expect(rt.approximateSize == ref.approximateSize)
                #expect(rt.originDeviceId == ref.originDeviceId)
                #expect(rt.addedAt == ref.addedAt)
                #expect(rt.caption == ref.caption)
            case .image(let image):
                guard case .image(let rt) = roundTripped.payload else {
                    Issue.record("expected image payload"); continue
                }
                #expect(rt.originalAssetId == image.originalAssetId)
                #expect(rt.thumbnailAssetId == image.thumbnailAssetId)
                #expect(rt.caption == image.caption)
            case .screenshot(let shot):
                guard case .screenshot(let rt) = roundTripped.payload else {
                    Issue.record("expected screenshot payload"); continue
                }
                #expect(rt.originalAssetId == shot.originalAssetId)
                #expect(rt.thumbnailAssetId == shot.thumbnailAssetId)
                #expect(rt.applicationName == shot.applicationName)
                #expect(rt.windowTitle == shot.windowTitle)
                #expect(rt.caption == shot.caption)
                #expect(rt.capturedAt == shot.capturedAt)
                #expect(rt.isCover == shot.isCover)
            }
        }

        // Asset sidecar round-trip.
        #expect(importedBytes.count == 2)
        #expect(importedBytes[UUID(uuidString: "a0000000-0000-4000-8000-000000000001")!] == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test
    func fileReferenceExportsGenericMetadataOnly() throws {
        let (note, blocks) = makeFullNote()
        let document = try NoteDocumentSerializer.exportDocument(note: note, blocks: blocks)
        let json = String(data: try NoteDocumentSerializer.encodeDocument(document), encoding: .utf8)!

        // No bookmark bytes / absolute paths anywhere (FR-105).
        #expect(!json.contains("bookmark"))
        #expect(!json.contains("/Users/"))
        #expect(!json.contains("file://"))
        // Generic metadata present.
        #expect(json.contains("report.pdf"))
        #expect(json.contains("com.adobe.pdf"))
    }

    @Test
    func unsupportedSchemaVersionFailsClosed() throws {
        let (note, blocks) = makeFullNote()
        let document = try NoteDocumentSerializer.exportDocument(note: note, blocks: blocks)
        let data = try NoteDocumentSerializer.encodeDocument(document)

        // Corrupt the schemaVersion to 99.
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["schemaVersion"] = 99
        let corrupted = try JSONSerialization.data(withJSONObject: object)

        do {
            _ = try NoteDocumentSerializer.decodeDocument(from: corrupted)
            Issue.record("unsupported schemaVersion must fail closed")
        } catch let error as NoteDocumentError {
            guard case .unsupportedSchemaVersion(99) = error else {
                Issue.record("wrong error: \(error)")
                return
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test
    func corruptedEnvelopeFailsClosed() throws {
        // Missing required keys.
        let missingKeys = #"{"schemaVersion":1,"id":"bad"}"#
        do {
            _ = try NoteDocumentSerializer.decodeDocument(from: Data(missingKeys.utf8))
            Issue.record("missing required keys must fail closed")
        } catch let error as NoteDocumentError {
            guard case .corruptedEnvelope = error else {
                Issue.record("wrong error: \(error)")
                return
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }

        // Unknown extra keys (additionalProperties: false).
        let extraKey = #"{"schemaVersion":1,"id":"bad","extra":1}"#
        do {
            _ = try NoteDocumentSerializer.decodeDocument(from: Data(extraKey.utf8))
            Issue.record("extra keys must fail closed")
        } catch let error as NoteDocumentError {
            guard case .corruptedEnvelope = error else {
                Issue.record("wrong error: \(error)")
                return
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }

        // Garbage bytes.
        do {
            _ = try NoteDocumentSerializer.decodeDocument(from: Data("not json at all".utf8))
            Issue.record("garbage must fail closed")
        } catch let error as NoteDocumentError {
            guard case .invalidDocumentData = error else {
                Issue.record("wrong error: \(error)")
                return
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test
    func validationCatchesOutOfRangeRichText() throws {
        let (note, blocks) = makeFullNote()
        // Corrupt a rich-text run beyond the text length.
        var corrupted = blocks
        let doc = RichTextDocument(
            text: "abc",
            paragraphs: [RichTextParagraph(startScalar: 0, endScalar: 10, style: .body, runs: [])]
        )
        corrupted[0] = Block(
            id: corrupted[0].id,
            noteId: note.id,
            kind: .richText,
            sortKey: 0,
            payload: .richText(doc),
            lastModifiedDeviceId: Self.deviceId
        )
        let document = try NoteDocumentSerializer.exportDocument(note: note, blocks: corrupted)
        #expect(NoteDocumentSerializer.validateForImport(document) != nil)
    }

    @Test
    func importValidationPassesForValidDocument() throws {
        let (note, blocks) = makeFullNote()
        let document = try NoteDocumentSerializer.exportDocument(note: note, blocks: blocks)
        #expect(NoteDocumentSerializer.validateForImport(document) == nil)
    }
}
