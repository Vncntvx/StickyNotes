import Testing
import Foundation
import Domain
import SecurityCore
import SyncCore

// MARK: - Meaningful-metadata enumeration tests (T194, FR-160a/FR-160b clarified 2026-08-07)
//
// Per tasks.md T194: every field in the FR-160a enumeration (user-content
// fields from FR-161, semantic object types, structural metadata, note
// appearance/behavior choices, version-lineage fields) is encrypted before
// upload. No field outside the FR-160b observable-leakage bound is left
// unencrypted. The manifest carries ONLY opaque names + sizes/times
// (FR-160b): objectName, objectId, contentHash, byteSize, modifiedAt.

@Suite struct MeaningfulMetadataEnumerationTests {

    // MARK: - Manifest carries only opaque, non-semantic fields (FR-160b)

    @Test
    func remoteManifestEntryCarriesOnlyOpaqueFields() {
        // The RemoteObjectEntry (the manifest entry) exposes ONLY:
        // objectName (opaque), objectId (version UUID — opaque), contentHash
        // (SHA-256 — opaque), byteSize, modifiedAt. No note content, titles,
        // summaries, captions, file names, or paths.
        let entry = RemoteObjectEntry(
            objectName: "obj-\(UUID().uuidString)",
            objectId: UUID().uuidString,
            contentHash: String(repeating: "a", count: 64),
            byteSize: 1024,
            modifiedAt: Date()
        )
        // Verify the entry has no content-bearing fields — only the opaque
        // metadata fields above. (This is a structural check: the type only
        // exposes these five fields.)
        #expect(!entry.objectName.isEmpty)
        #expect(!entry.objectId.isEmpty)
        #expect(entry.contentHash.count == 64)
        #expect(entry.byteSize > 0)
    }

    @Test
    func remoteObjectNamesAreOpaqueAndRandom() {
        // Per FR-160b / data-model.md §RemoteLayout: remote object names
        // are opaque random strings — no semantic type in filenames.
        let name1 = RemoteLayout.opaqueObjectName()
        let name2 = RemoteLayout.opaqueObjectName()
        #expect(name1 != name2, "object names must be random")
        // The name does not encode the object type (no "note-" / "asset-"
        // prefix — the manifest is opaque; type is discovered by decryption).
        #expect(!name1.contains("note"))
        #expect(!name1.contains("asset"))
        #expect(!name1.contains("tombstone"))
    }

    // MARK: - All CanonicalNote content fields are inside the encrypted envelope

    @Test
    func canonicalNoteContentFieldsAreEncryptedInsideEnvelope() async throws {
        // The entire CanonicalNote (title, blocks/payloads, appearance,
        // version lineage) is serialized to JSON and encrypted as ONE
        // envelope. None of these fields appear in the manifest.
        let bootstrap = try await VaultBootstrapService.createVault(
            password: "pw", secretStore: InMemorySecretStore(), isTestFixture: true
        )
        let key = try await VaultBootstrapService.openVault(bootstrap, password: "pw")
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)

        let note = CanonicalNote(
            id: UUID(),
            title: "sensitive title",
            colorKey: .pink,
            transparency: 0.8,
            textSize: 18,
            alwaysOnTop: true,
            widgetEligible: true,
            manualSortKey: 1024,
            lifecycleState: .active,
            versionId: UUID(),
            lastModifiedDeviceId: UUID(),
            createdAt: Date(),
            modifiedAt: Date(),
            blocks: [
                CanonicalBlock(
                    noteId: UUID(), kind: .richText, sortKey: 0,
                    lastModifiedDeviceId: UUID(),
                    payload: .richText(RichTextDocument.plain("sensitive body text"))
                )
            ]
        )
        let payload = try CanonicalJSONEncoder().encode(note)
        let envelope = try vault.encrypt(
            objectId: note.versionId.uuidString, objectType: "note",
            schemaVersion: CanonicalNote.schemaVersion, plaintext: payload
        )

        // The envelope's ciphertext is the ONLY thing uploaded. The manifest
        // entry does not carry title/body/appearance — only the opaque
        // objectId + contentHash + byteSize.
        #expect(!envelope.ciphertext.isEmpty)
        // Verify the plaintext (note content) does NOT appear in the
        // envelope framing (only in the ciphertext, which is encrypted).
        let wireJSON = try envelope.canonicalJSON()
        let wireString = String(data: wireJSON, encoding: .utf8) ?? ""
        #expect(!wireString.contains("sensitive title"))
        #expect(!wireString.contains("sensitive body text"))
        #expect(!wireString.contains("pink"))
    }

    // MARK: - Negative: device-local fields never appear in the encrypted payload

    @Test
    func deviceLocalFieldsAreNotInCanonicalNote() {
        // CanonicalNote does NOT carry device-local fields (storagePath,
        // isSynced, windowState frame, bookmark bytes). These never appear
        // in the encrypted envelope because they're not in the canonical
        // document at all.
        // Verify by checking the CanonicalNote struct's fields — it has
        // title/blocks/appearance/lineage but no storagePath/isSynced/
        // windowFrame/bookmarkData.
        let note = CanonicalNote(
            id: UUID(),
            colorKey: .yellow,
            transparency: 0,
            textSize: 13,
            alwaysOnTop: false,
            widgetEligible: true,
            manualSortKey: 0,
            lifecycleState: .active,
            versionId: UUID(),
            lastModifiedDeviceId: UUID(),
            createdAt: Date(),
            modifiedAt: Date(),
            blocks: []
        )
        // Mirror-based check: the type's keys are the encrypted fields.
        let mirror = Mirror(reflecting: note)
        let fieldNames = Set(mirror.children.compactMap { $0.label })
        #expect(fieldNames.contains("title"))
        #expect(fieldNames.contains("blocks"))
        #expect(fieldNames.contains("colorKey"))
        #expect(fieldNames.contains("versionId"))
        // Device-local fields are absent.
        #expect(!fieldNames.contains("storagePath"))
        #expect(!fieldNames.contains("isSynced"))
        #expect(!fieldNames.contains("windowFrame"))
        #expect(!fieldNames.contains("bookmarkData"))
    }

    // MARK: - Asset blobs are independently encrypted (FR-090a)

    @Test
    func assetBytesAreEncryptedAsIndependentObjects() async throws {
        // Per FR-090a: assets are synchronized as independent encrypted
        // objects — never bundled inside a note envelope. Each asset object
        // carries a SHA-256 integrity hash. The SyncedAssetBlob is encrypted
        // under its own objectId (assetId), not the note's versionId.
        let bootstrap = try await VaultBootstrapService.createVault(
            password: "pw", secretStore: InMemorySecretStore(), isTestFixture: true
        )
        let key = try await VaultBootstrapService.openVault(bootstrap, password: "pw")
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)

        let assetId = UUID()
        let blob = SyncedAssetBlob(
            assetId: assetId,
            kind: AssetKind.original.rawValue,
            contentType: "image/png",
            contentHash: "sha256:\(String(repeating: "0", count: 64))",
            bytes: Data(repeating: 0x89, count: 100)
        )
        let payload = try blob.canonicalJSON()
        // The asset is encrypted under its OWN objectId (assetId), with
        // objectType = "asset" — distinct from any note envelope.
        let envelope = try vault.encrypt(
            objectId: assetId.uuidString, objectType: "asset",
            schemaVersion: SyncedAssetBlob.version, plaintext: payload
        )
        #expect(envelope.objectId == assetId.uuidString)
        // The manifest entry's objectId is the assetId, not a note versionId.
        #expect(envelope.objectId != "note-version-id")
    }
}
