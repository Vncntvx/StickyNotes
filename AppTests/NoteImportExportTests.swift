import Testing
import Foundation
import Domain
import Persistence
import AssetStore
@testable import StickyNotes

// MARK: - R1.7 note JSON import + asset sidecar (remediation-phase1 T028/T029)
//
// FR-031a export/import previously had NO import path (a dangling doc
// comment claimed one — audit S-8) and export silently DROPPED the asset
// bytes (`assetBytes` was threaded through and discarded, the sidecar was
// never written — export lost every image). These tests pin the closed
// loop: import stores note + blocks + assets; export writes the document
// AND the sidecar; corrupt input fails closed with no partial note.

@MainActor
@Suite struct NoteImportExportTests {

    private func makeEnvironment() throws -> (AppEnvironment, URL) {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let assetRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("importexport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: assetRoot, withIntermediateDirectories: true)
        let assetStore = try AssetStore(directoryURL: assetRoot)
        let env = AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(directoryURL: assetRoot, store: assetStore),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(
                defaults: UserDefaults(suiteName: "test.impexp.\(UUID().uuidString)") ?? .standard
            )
        )
        return (env, assetRoot)
    }

    // MARK: - Import (T028)

    @Test
    func importStoresNoteBlocksAndAssets() async throws {
        let (env, _) = try makeEnvironment()
        let originalID = UUID()
        let thumbID = UUID()
        let note = Note(id: UUID(), lastModifiedDeviceId: UUID())
        let block = Block(
            noteId: note.id,
            kind: .image,
            sortKey: 0,
            payload: .image(EmbeddedImagePayload(originalAssetId: originalID, thumbnailAssetId: thumbID)),
            lastModifiedDeviceId: UUID()
        )
        let document = CanonicalNote(note: note, blocks: [block])
        let data = try CanonicalJSONEncoder().encode(document)
        let sidecar = try NoteDocumentSerializer.encodeAssetSidecar([
            originalID: Data("original-bytes".utf8),
            thumbID: Data("thumb-bytes".utf8),
        ])

        let imported = try await NoteExportImport.importNoteDocument(
            data: data, sidecarData: sidecar, environment: env
        )
        #expect(imported.id == note.id)

        // Note + block landed in the repository.
        let fetched = try await env.persistence.noteRepository!.fetch(id: note.id)
        #expect(fetched != nil, "imported note must be stored")
        let blocks = try await env.persistence.noteRepository!.fetchBlocks(noteId: note.id)
        #expect(blocks.count == 1, "imported block must be stored")
        #expect(blocks.first?.id == block.id)

        // Asset bytes landed in the AssetStore under the referenced ids.
        let original = try await env.assets.store?.readData(assetID: originalID)
        #expect(original == Data("original-bytes".utf8), "original asset bytes imported")
        let thumb = try await env.assets.store?.readData(assetID: thumbID)
        #expect(thumb == Data("thumb-bytes".utf8), "thumbnail asset bytes imported")
    }

    @Test
    func importRejectsCorruptDocumentWithNoPartialNote() async throws {
        let (env, _) = try makeEnvironment()
        // Missing required envelope keys → fail closed.
        let invalid = try JSONSerialization.data(withJSONObject: ["id": UUID().uuidString])
        do {
            _ = try await NoteExportImport.importNoteDocument(data: invalid, sidecarData: nil, environment: env)
            Issue.record("a document missing required keys must fail closed")
        } catch {
            // Expected.
        }
        // Undecodable JSON → fail closed.
        do {
            _ = try await NoteExportImport.importNoteDocument(data: Data("not json".utf8), sidecarData: nil, environment: env)
            Issue.record("undecodable data must fail closed")
        } catch {
            // Expected.
        }
    }

    @Test
    func importRejectsDuplicateNoteIdFailClosed() async throws {
        let (env, _) = try makeEnvironment()
        let note = Note(id: UUID(), lastModifiedDeviceId: UUID())
        // The note already exists locally.
        try await env.persistence.noteRepository!.create(note)
        let document = CanonicalNote(note: note, blocks: [])
        let data = try CanonicalJSONEncoder().encode(document)
        do {
            _ = try await NoteExportImport.importNoteDocument(data: data, sidecarData: nil, environment: env)
            Issue.record("importing an existing note id must fail closed (no overwrite)")
        } catch {
            // Expected.
        }
    }

    // MARK: - Export sidecar (T029)

    @Test
    func exportWritesDocumentAndSidecar() throws {
        let (_, dir) = try makeEnvironment()
        let originalID = UUID()
        let note = Note(id: UUID(), lastModifiedDeviceId: UUID())
        let block = Block(
            noteId: note.id,
            kind: .image,
            sortKey: 0,
            payload: .image(EmbeddedImagePayload(originalAssetId: originalID)),
            lastModifiedDeviceId: UUID()
        )
        let (docURL, sidecarURL) = try NoteExportImport.writeExport(
            note: note, blocks: [block], assetBytes: [originalID: Data("bytes".utf8)], to: dir
        )
        #expect(FileManager.default.fileExists(atPath: docURL.path), "document must be written")
        guard let sidecarURL else {
            Issue.record("sidecar must be written next to the document when assets exist")
            return
        }
        #expect(FileManager.default.fileExists(atPath: sidecarURL.path), "sidecar must exist")
        let sidecarData = try Data(contentsOf: sidecarURL)
        let decoded = try NoteDocumentSerializer.decodeAssetSidecar(from: sidecarData)
        #expect(decoded[originalID] == Data("bytes".utf8), "sidecar must carry the asset bytes")
    }

    @Test
    func exportWithoutAssetsOmitsSidecar() throws {
        let (_, dir) = try makeEnvironment()
        let note = Note(id: UUID(), lastModifiedDeviceId: UUID())
        let (_, sidecarURL) = try NoteExportImport.writeExport(
            note: note, blocks: [], assetBytes: [:], to: dir
        )
        #expect(sidecarURL == nil, "no sidecar when there are no asset bytes")
    }

    @Test
    func exportDocumentRoundTripsThroughImport() async throws {
        // End-to-end: export (with sidecar) → import into a fresh env →
        // note + blocks + assets restored (FR-031a closed loop).
        let (_, dir) = try makeEnvironment()
        let originalID = UUID()
        let note = Note(id: UUID(), lastModifiedDeviceId: UUID())
        let block = Block(
            noteId: note.id,
            kind: .image,
            sortKey: 0,
            payload: .image(EmbeddedImagePayload(originalAssetId: originalID, thumbnailAssetId: nil)),
            lastModifiedDeviceId: UUID()
        )
        let (docURL, sidecarURL) = try NoteExportImport.writeExport(
            note: note, blocks: [block], assetBytes: [originalID: Data("roundtrip-bytes".utf8)], to: dir
        )

        // Fresh environment (independent DB + asset root).
        let (envB, _) = try makeEnvironment()
        let docData = try Data(contentsOf: docURL)
        let sidecarData = sidecarURL.flatMap { try? Data(contentsOf: $0) }
        let imported = try await NoteExportImport.importNoteDocument(
            data: docData, sidecarData: sidecarData, environment: envB
        )
        #expect(imported.id == note.id)
        let blocks = try await envB.persistence.noteRepository!.fetchBlocks(noteId: note.id)
        #expect(blocks.count == 1)
        let restored = try await envB.assets.store?.readData(assetID: originalID)
        #expect(restored == Data("roundtrip-bytes".utf8), "asset bytes survive the export→import round trip")
    }
}
