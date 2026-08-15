import Testing
import Foundation
import Domain
import SecurityCore
import SyncCore

// MARK: - R3.3 canonicalJSON convergence tests (T013/T014)
//
// Per remediation roadmap 2026-08-15 R3.3 (M-9): four hand-rolled
// `sortedKeys` encoders (EncryptedEnvelope/VaultBootstrap/SyncedAssetBlob/
// DiagnosticBundle) must converge on `Domain.CanonicalJSONEncoder` — the
// single project-wide canonical boundary (stable keys, ISO 8601 UTC with
// millisecond precision + `Z` suffix). Each type's own `canonicalJSON()`
// must produce byte-identical output to the canonical encoder.

@Suite struct CanonicalJSONConvergenceTests {

    @Test func envelopeMatchesCanonicalEncoder() throws {
        let envelope = EncryptedEnvelope(
            objectId: "obj-1",
            nonce: Data([1, 2, 3, 4]),
            ciphertext: Data([9, 8, 7])
        )
        let own = try envelope.canonicalJSON()
        let canonical = try CanonicalJSONEncoder().encode(envelope)
        #expect(own == canonical,
                "EncryptedEnvelope.canonicalJSON() must equal CanonicalJSONEncoder output")
        // Round-trip through the canonical DECODER must also succeed (the
        // date strategy must match, not just the byte layout).
        let decoded = try CanonicalJSONDecoder().decode(EncryptedEnvelope.self, from: own)
        #expect(decoded == envelope)
    }

    @Test func vaultBootstrapWithDatesMatchesCanonicalEncoder() async throws {
        // Real vault creation (Argon2id parameters + wrapped key are
        // domain-typed; hand-building them would duplicate production
        // construction).
        let bootstrap = try await VaultBootstrapService.createVault(
            password: "convergence-test-password",
            secretStore: InMemorySecretStore(),
            isTestFixture: true
        )
        let own = try bootstrap.canonicalJSON()
        let canonical = try CanonicalJSONEncoder().encode(bootstrap)
        #expect(own == canonical,
                "VaultBootstrap.canonicalJSON() (ISO 8601 with fractional seconds) must equal canonical encoder")
        let decoded = try CanonicalJSONDecoder().decode(VaultBootstrap.self, from: own)
        // The canonical date format has millisecond precision — sub-ms
        // precision is intentionally truncated on round-trip.
        #expect(decoded.vaultId == bootstrap.vaultId)
        #expect(decoded.vaultLocator == bootstrap.vaultLocator)
        #expect(decoded.argon2id == bootstrap.argon2id)
        #expect(decoded.wrappedMasterKey == bootstrap.wrappedMasterKey)
        #expect(decoded.keyConfirmation == bootstrap.keyConfirmation)
        #expect(decoded.encryptionSuiteVersion == bootstrap.encryptionSuiteVersion)
        #expect(abs(decoded.createdAt.timeIntervalSince(bootstrap.createdAt)) < 0.002,
                "createdAt round-trip within the canonical millisecond precision")
    }

    @Test func syncedAssetBlobMatchesCanonicalEncoder() throws {
        let blob = SyncedAssetBlob(
            blobVersion: SyncedAssetBlob.version,
            assetId: UUID(uuidString: "B2C3D4E5-F6A7-4B6C-9D8E-7F6A5B4C3D2E")!,
            kind: "original",
            contentType: "image/png",
            contentHash: "sha256:abcd",
            bytes: Data([0x89, 0x50, 0x4E, 0x47])
        )
        let own = try blob.canonicalJSON()
        let canonical = try CanonicalJSONEncoder().encode(blob)
        #expect(own == canonical,
                "SyncedAssetBlob.canonicalJSON() must equal CanonicalJSONEncoder output")
        let decoded = try CanonicalJSONDecoder().decode(SyncedAssetBlob.self, from: own)
        #expect(decoded == blob)
    }

    @Test func diagnosticBundleMatchesCanonicalEncoder() throws {
        let bundle = DiagnosticBundle(
            appVersion: "0.1",
            osVersion: "macOS 26",
            schemaVersionLocal: 1,
            providerType: "webdav",
            recentErrorEvents: [
                DiagnosticErrorEvent(
                    timestamp: Date(timeIntervalSince1970: 1_700_000_100),
                    normalizedErrorCategory: "auth"
                ),
            ],
            syncRunCounts: DiagnosticSyncRunCounts(last24h: 3, last7d: 5, last30d: 9),
            objectCounts: DiagnosticObjectCounts(notes: 10, blocks: 20),
            vaultState: DiagnosticVaultState.locked,
            permissionStatuses: DiagnosticPermissionStatuses(
                screenRecording: true,
                accessibility: false
            ),
            generatedAt: Date(timeIntervalSince1970: 1_700_000_123)
        )
        let own = try DiagnosticBundleGenerator.encode(bundle)
        let canonical = try CanonicalJSONEncoder().encode(bundle)
        #expect(own == canonical,
                "DiagnosticBundleGenerator.encode must equal CanonicalJSONEncoder output")
        let decoded = try CanonicalJSONDecoder().decode(DiagnosticBundle.self, from: own)
        #expect(decoded == bundle)
    }
}
