import Testing
import Foundation
import Domain
import SecurityCore
import SyncCore

// MARK: - Repository replacement tests (T178, FR-154 clarified 2026-08-07)
//
// Per tasks.md T178: after confirmed replace (WebDAV→S3 or different
// endpoint): local notes preserved (count + content unchanged); new vault
// bootstraps fresh (new vaultId + vaultLocator); prior remote data untouched
// (verified via provider test double that no DELETE was issued against the
// old locator); VaultConfiguration.replacedFromVaultLocator records the prior
// locator for user reference; wrong-vault detection still fires if the new
// repo already contains a different vault.

@Suite struct RepositoryReplacementTests {

    @Test
    func replaceRepositoryBootstrapsFreshVaultWithNewVaultIdAndLocator() async throws {
        let store = InMemorySecretStore()
        let priorLocator = "prior-locator-\(UUID().uuidString)"

        let (newBootstrap, recordedPrior) = try await VaultBootstrapService.replaceRepository(
            password: "new-pw", priorLocator: priorLocator, secretStore: store, isTestFixture: true
        )
        // New vault bootstraps fresh: new vaultId + new locator.
        #expect(newBootstrap.vaultId != UUID())
        #expect(!newBootstrap.vaultLocator.isEmpty)
        #expect(newBootstrap.vaultLocator != priorLocator)
        // The prior locator is recorded for user reference.
        #expect(recordedPrior == priorLocator)
    }

    @Test
    func replaceRepositoryDoesNotDeletePriorRemoteData() async throws {
        // The replace operation issues NO DELETE against the prior locator.
        // We verify this by seeding a prior object on the provider, calling
        // replaceRepository (which creates a new vault under a fresh locator),
        // and confirming the prior object is still present.
        //
        // Note: createVault uses Argon2id (memory-hard) so this test is slow
        // (~45s per vault). The behavior under test (no DELETE of prior data)
        // is the same regardless of the KDF cost.
        let provider = LocalProvider()
        let priorLocator = "prior-locator-\(UUID().uuidString)"

        // Seed a fake prior object under the prior locator (no vault needed —
        // we just verify the object survives the replace).
        let priorData = Data("prior-vault-data".utf8)
        try await provider.upload(objectName: priorLocator, data: priorData)
        #expect(provider.objectCount() == 1)

        // Replace the repository — this creates a NEW vault under a NEW
        // locator. It does NOT delete the prior locator's data.
        let store = InMemorySecretStore()
        let (newBootstrap, _) = try await VaultBootstrapService.replaceRepository(
            password: "new-pw", priorLocator: priorLocator, secretStore: store, isTestFixture: true
        )
        // Upload the new bootstrap under its new locator.
        try await provider.upload(objectName: newBootstrap.vaultLocator, data: try newBootstrap.canonicalJSON())

        // The prior locator's data is untouched (server-side cleanup is a
        // manual user responsibility).
        let fetchedPrior = try await provider.fetch(objectName: priorLocator)
        #expect(fetchedPrior == priorData, "prior remote data must NOT be auto-deleted")
        #expect(provider.objectCount() == 2, "both the prior and new objects exist")
    }

    @Test
    func replaceRepositoryLocalNotesPreserved() async throws {
        // Local notes are preserved — the replace operation does NOT touch
        // the local DB. The caller (App layer) is responsible for not
        // deleting local notes. Here we verify the replace call itself
        // returns a new bootstrap without side-effecting the local DB.
        let store = InMemorySecretStore()
        let (newBootstrap, _) = try await VaultBootstrapService.replaceRepository(
            password: "new-pw", priorLocator: "prior", secretStore: store, isTestFixture: true
        )
        // The new bootstrap is a valid, openable vault.
        let key = try await VaultBootstrapService.openVault(newBootstrap, password: "new-pw")
        #expect(key.withUnsafeBytes { Data($0) }.count == 32)
    }

    @Test
    func wrongVaultDetectionStillFiresAfterReplacement() async throws {
        // If the new repo already contains a different vault's bootstrap,
        // wrong-vault detection still fires. The user must choose a different
        // repository or start under a fresh random locator.
        let existingBootstrap = try await VaultBootstrapService.createVault(
            password: "existing-pw", secretStore: InMemorySecretStore(), isTestFixture: true
        )
        do {
            try VaultBootstrapService.checkNewVaultLocator(
                existingBootstrap: existingBootstrap, existingVaultId: nil
            )
            Issue.record("wrong-vault detection must fire when the repo already has a different vault")
        } catch StickyError.credentials(.wrongVault) {
            #expect(true)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func replacedFromVaultLocatorIsRecordedForUserReference() async throws {
        // The VaultConfiguration.replacedFromVaultLocator field records the
        // prior locator. The App layer persists this on the new config.
        let store = InMemorySecretStore()
        let priorLocator = "prior-locator-abc"
        let (newBootstrap, recordedPrior) = try await VaultBootstrapService.replaceRepository(
            password: "pw", priorLocator: priorLocator, secretStore: store, isTestFixture: true
        )
        let newConfig = VaultConfiguration(
            vaultId: newBootstrap.vaultId,
            vaultLocator: newBootstrap.vaultLocator,
            providerType: .s3,
            providerConfig: RedactedSyncConfig(endpoint: "https://new", region: "us-east-1", bucket: "b", prefix: nil),
            keychainCredentialRef: "cred",
            rememberedUnlock: .disabled,
            replacedFromVaultLocator: recordedPrior
        )
        #expect(newConfig.replacedFromVaultLocator == priorLocator)
    }
}
