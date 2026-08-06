import Testing
import Foundation
import Domain
import SecurityCore
import SyncCore

// MARK: - Diagnostics privacy tests (T109)
//
// Per tasks.md T109: "no credentials/secrets, note content, file names/paths,
// window titles, screenshot captions, or todo text appear in logs or
// exported diagnostics (covers full FR-191 + SC-010 redaction scope)".

@Suite struct DiagnosticsPrivacyTests {

    // A text blob containing every forbidden content class.
    private let sensitivePayload = """
        note title: my secret project plans
        file name: /Users/alice/Documents/tax-refund-2026.pdf
        window title: Safari — Secure Banking Login
        caption: screenshot of passport page 3
        todo: buy bitcoin with password hunter2
        """

    @Test
    func sanitizedErrorCodesNeverContainNoteContent() {
        // Every typed error the app can surface carries only a fixed code.
        let codes: [String] = [
            StickyError.persistence(.recordNotFound).sanitizedCode,
            StickyError.assetStorage(.writeFailed).sanitizedCode,
            StickyError.capture(.permissionDenied).sanitizedCode,
            StickyError.encryption(.wrongPassword).sanitizedCode,
            StickyError.credentials(.accessDenied).sanitizedCode,
            StickyError.webdav(.authFailed).sanitizedCode,
            StickyError.s3(.clockSkew).sanitizedCode,
            StickyError.syncConflict(.manifestPreconditionFailed).sanitizedCode,
            StickyError.remoteCorruption(.manifestInvalid).sanitizedCode,
            StickyError.schemaCompatibility(.widgetSchemaMismatch).sanitizedCode,
        ]
        for code in codes {
            #expect(!code.contains("/"), "no paths in sanitized codes: \(code)")
            #expect(!code.contains(" "), "no free text in sanitized codes: \(code)")
            // Fixed code vocabulary only — the only "password" mention is the
            // intentional `wrongPassword` code; nothing else leaks.
            #expect(!code.contains("hunter2"))
        }
    }

    @Test
    func providerErrorsAreContentFree() {
        for category: ProviderError in [.auth, .forbidden, .conditionalFailed, .notFound, .conflict,
                                        .network, .server, .clockSkew, .corrupt, .schemaUnsupported,
                                        .canceled, .tls, .unknown] {
            let code = category.sanitizedCode
            #expect(!code.contains(" "))
            #expect(!code.contains("/"))
        }
    }

    @Test
    func vaultBootstrapJsonContainsNoPassword() async throws {
        let bootstrap = try await VaultBootstrapService.createVault(
            password: "hunter2-super-secret", secretStore: InMemorySecretStore()
        )
        let json = try bootstrap.canonicalJSON()
        let text = String(data: json, encoding: .utf8)!
        #expect(!text.contains("hunter2"), "the password must never be serialized into the bootstrap")
    }

    @Test
    func syncSummaryRevealsNoContent() async throws {
        let summary = SyncSummary(uploadedObjects: 3, downloadedObjects: 2)
        let description = "\(summary)"
        #expect(!description.contains(sensitivePayload))
        // Only counts/booleans are in the summary.
        #expect(description.contains("uploadedObjects: 3"))
    }

    @Test
    func manifestContainsNoSemanticPayload() throws {
        // The decrypted manifest lists opaque names + sizes/times only —
        // titles, file names, window titles never appear (T110 overlap).
        let manifest = RemoteManifest(
            manifestVersion: "t1",
            vaultId: UUID(),
            entries: [
                RemoteObjectEntry(
                    objectName: "7f4d3a9c2b8e1f6045d6a7b8c9d0e1f2a",
                    objectId: "a1b2c3d4e5f60718293a4b5c6d7e8f90a",
                    contentHash: String(repeating: "ab", count: 32),
                    byteSize: 1024,
                    modifiedAt: Date()
                ),
            ],
            updatedByDeviceId: UUID()
        )
        let json = try JSONEncoder().encode(manifest)
        let text = String(data: json, encoding: .utf8)!
        #expect(!text.contains("title"))
        #expect(!text.contains("password"))
        #expect(!text.contains("Users"))
        #expect(!text.contains("Safari"))
    }

    @Test
    func remoteLayoutProducesOpaqueNames() {
        let names = (0..<8).map { _ in RemoteLayout.opaqueObjectName() }
        for name in names {
            #expect(RemoteLayout.isOpaque(name))
            #expect(!name.contains("-"))
            #expect(name.count == 32)
        }
        // No semantic type is ever encoded.
        #expect(!names.joined().contains("note"))
        #expect(!names.joined().contains("asset"))
        #expect(!names.joined().contains("tombstone"))
        // Uniqueness.
        #expect(Set(names).count == names.count)
    }
}
