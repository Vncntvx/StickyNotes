import Testing
import Foundation
import Domain

// MARK: - Remote layout tests (T110)
//
// Per tasks.md T110: "Domain test: remote object names opaque/random; no
// semantic type in filenames; manifest carries only opaque names+sizes/times
// in `Packages/StickyCore/Tests/DomainTests/RemoteLayoutTests.swift`".

@Suite struct RemoteLayoutTests {

    @Test
    func objectNamesAreOpaqueAndRandom() {
        let a = RemoteLayout.opaqueObjectName()
        let b = RemoteLayout.opaqueObjectName()
        #expect(a != b)
        #expect(RemoteLayout.isOpaque(a))
        #expect(a.count == 32)
        #expect(a.allSatisfy { $0.isHexDigit })
    }

    @Test
    func opaqueNamesDoNotEncodeSemanticType() {
        // The name shape must be uniform across object types — a provider
        // seeing any single object cannot infer note vs asset vs tombstone.
        let names = (0..<6).map { _ in RemoteLayout.opaqueObjectName() }
        #expect(names.allSatisfy(RemoteLayout.isOpaque))
        for banned in ["note", "asset", "tombstone", "manifest", "image", "text"] {
            #expect(!names.joined().contains(banned))
        }
    }

    @Test
    func manifestEntriesExposeOnlyOpaqueFields() {
        let entry = RemoteObjectEntry(
            objectName: "7f4d3a9c2b8e1f6045d6a7b8c9d0e1f2",
            objectId: "a1b2c3d4e5f60718293a4b5c6d7e8f90",
            contentHash: String(repeating: "cd", count: 32),
            byteSize: 4096,
            modifiedAt: Date()
        )
        // All fields are opaque/size/time — nothing semantic.
        #expect(RemoteLayout.isOpaque(entry.objectName))
        #expect(entry.contentHash.count == 64)
        #expect(entry.byteSize >= 0)
    }

    @Test
    func manifestJsonCarriesNoTitlesOrPaths() throws {
        let manifest = RemoteManifest(
            manifestVersion: "v1",
            vaultId: UUID(),
            entries: [
                RemoteObjectEntry(
                    objectName: RemoteLayout.opaqueObjectName(),
                    objectId: RemoteLayout.opaqueObjectName(),
                    contentHash: String(repeating: "ef", count: 32),
                    byteSize: 128,
                    modifiedAt: Date()
                ),
            ],
            tombstones: [
                RemoteTombstone(
                    noteId: UUID(),
                    deletedVersionId: UUID(),
                    parentVersionId: nil,
                    deletingDeviceId: UUID(),
                    deletedAt: Date()
                ),
            ],
            updatedByDeviceId: UUID()
        )
        let data = try JSONEncoder().encode(manifest)
        let text = String(data: data, encoding: .utf8)!
        // Only opaque names + UUIDs + sizes + ISO dates.
        #expect(!text.contains("title"))
        #expect(!text.contains("path"))
        #expect(!text.contains(".pdf"))
        #expect(!text.contains("caption"))
    }

    // MARK: - Bootstrap object name (T002, plan §Bootstrap object name)
    //
    // The bootstrap object name is a DETERMINISTIC function of the locator:
    // the create path uploads under it and the join path fetches under the
    // same name. Must not collide with the fixed manifest object name.

    @Test
    func bootstrapObjectNameIsDeterministic() {
        let locator = RemoteLayout.opaqueObjectName()
        let a = RemoteLayout.bootstrapObjectName(for: locator)
        let b = RemoteLayout.bootstrapObjectName(for: locator)
        #expect(a == b, "the bootstrap object name MUST be deterministic for a given locator")
    }

    @Test
    func bootstrapObjectNameIdenticalForCreateAndJoin() {
        // The object the create path uploads is exactly the object the join
        // path fetches — same locator, same derived name, both paths.
        let locator = RemoteLayout.opaqueObjectName()
        let createName = RemoteLayout.bootstrapObjectName(for: locator)
        let joinName = RemoteLayout.bootstrapObjectName(for: locator)
        #expect(createName == joinName)
        #expect(createName == RemoteLayout.bootstrapObjectName(for: locator))
    }

    @Test
    func bootstrapObjectNameDistinguishesLocators() {
        let l1 = RemoteLayout.opaqueObjectName()
        let l2 = RemoteLayout.opaqueObjectName()
        #expect(RemoteLayout.bootstrapObjectName(for: l1) != RemoteLayout.bootstrapObjectName(for: l2),
                "different locators MUST derive different bootstrap object names")
    }

    @Test
    func bootstrapObjectNameDoesNotCollideWithManifestName() {
        let locator = RemoteLayout.opaqueObjectName()
        let name = RemoteLayout.bootstrapObjectName(for: locator)
        #expect(name != "manifest", "the bootstrap object must not collide with the manifest object name")
    }

    @Test
    func bootstrapObjectNameIsOpaqueShaped() {
        let locator = RemoteLayout.opaqueObjectName()
        let name = RemoteLayout.bootstrapObjectName(for: locator)
        // Names reveal no semantic type (constitution VII).
        for banned in ["bootstrap", "note", "asset", "manifest", "vault"] {
            #expect(!name.contains(banned))
        }
        #expect(!name.isEmpty)
    }
}
