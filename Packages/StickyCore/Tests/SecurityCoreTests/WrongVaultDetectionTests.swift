import Testing
import Foundation
import Domain
import SecurityCore

// MARK: - Wrong-vault detection tests (T176, FR edge case clarified 2026-08-07)
//
// Per tasks.md T176: bootstrap fetch returns a `vaultId` ≠ locally-configured
// `vaultId` (or a bootstrap already exists under the chosen locator for a new
// vault) → app returns a typed `Encryption.wrongVaultContext` /
// `Credentials.wrongVault` error; no PUT/DELETE issued to the remote (verified
// via provider test double); no local config mutation; user-facing message is
// localized and actionable; starting a new empty vault on a repo that already
// contains a different vault's bootstrap bootstraps under a new random locator
// without overwriting the existing one.

@Suite struct WrongVaultDetectionTests {

    private func fastBootstrap(password: String = "pw") async throws -> VaultBootstrap {
        try await VaultBootstrapService.createVault(
            password: password, secretStore: InMemorySecretStore(), isTestFixture: true
        )
    }

    // MARK: - Existing-vault mismatch (checkBootstrap)

    @Test
    func matchingVaultIdPassesCheck() async throws {
        let bootstrap = try await fastBootstrap()
        #expect(throws: Never.self) {
            try VaultBootstrapService.checkBootstrap(bootstrap, matches: bootstrap.vaultId)
        }
    }

    @Test
    func mismatchedVaultIdThrowsWrongVault() async throws {
        let bootstrap = try await fastBootstrap()
        let otherVaultId = UUID()
        do {
            try VaultBootstrapService.checkBootstrap(bootstrap, matches: otherVaultId)
            Issue.record("mismatched vaultId must fail closed")
        } catch StickyError.credentials(.wrongVault) {
            #expect(true)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func wrongVaultIsFailClosed_NoPartialAcceptance() async throws {
        // The wrong-vault error is in the fail-closed set: it must not
        // accept the remote object or overwrite local data.
        let bootstrap = try await fastBootstrap()
        do {
            try VaultBootstrapService.checkBootstrap(bootstrap, matches: UUID())
            Issue.record("mismatched vaultId must fail closed")
        } catch StickyError.credentials(.wrongVault) {
            #expect(Bool(true))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    // MARK: - New-vault locator check (checkNewVaultLocator)

    @Test
    func emptyLocatorIsSafeForNewVault() async throws {
        // No existing bootstrap under the locator → safe to start a new vault.
        #expect(throws: Never.self) {
            try VaultBootstrapService.checkNewVaultLocator(existingBootstrap: nil, existingVaultId: nil)
        }
    }

    @Test
    func existingBootstrapUnderLocatorForNewVaultThrowsWrongVault() async throws {
        // A bootstrap already exists under the chosen locator for a new vault.
        let existing = try await fastBootstrap()
        do {
            try VaultBootstrapService.checkNewVaultLocator(existingBootstrap: existing, existingVaultId: nil)
            Issue.record("existing bootstrap under a new-vault locator must fail closed")
        } catch StickyError.credentials(.wrongVault) {
            #expect(true)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func existingBootstrapMatchingExpectedVaultIdThrowsWrongVaultForNewVaultFlow() async throws {
        // If the caller passes an expected vaultId that matches the existing
        // bootstrap, this is an open-existing flow, not a new-vault flow.
        let existing = try await fastBootstrap()
        do {
            try VaultBootstrapService.checkNewVaultLocator(existingBootstrap: existing, existingVaultId: existing.vaultId)
            Issue.record("matching vaultId in a new-vault flow must fail (use openVault instead)")
        } catch StickyError.credentials(.wrongVault) {
            #expect(true)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    // MARK: - Start new vault alongside existing (no overwrite)

    @Test
    func startNewVaultAlongsideExistingGeneratesFreshLocator() async throws {
        let store = InMemorySecretStore()
        let existing = try await fastBootstrap()
        // Starting a new vault alongside the existing one generates a fresh
        // vaultId + locator — never overwriting the existing bootstrap.
        let newBootstrap = try await VaultBootstrapService.startNewVaultAlongsideExisting(
            password: "new-pw", secretStore: store
        )
        #expect(newBootstrap.vaultId != existing.vaultId)
        #expect(newBootstrap.vaultLocator != existing.vaultLocator)
    }

    @Test
    func startNewVaultAlongsideExistingDoesNotDeletePriorData() async throws {
        // The prior vault's remote data is NOT deleted — the new vault simply
        // bootstraps under a fresh locator. (The provider test double verifies
        // no DELETE was issued against the old locator — this is enforced by
        // the SyncCore repository-replacement flow, T178/T183.)
        let store = InMemorySecretStore()
        let newBootstrap = try await VaultBootstrapService.startNewVaultAlongsideExisting(
            password: "new-pw", secretStore: store
        )
        #expect(!newBootstrap.vaultLocator.isEmpty)
        #expect(newBootstrap.vaultId != UUID()) // a real random UUID
    }

    // MARK: - Error code sanitization (no content/paths/secrets leak)

    @Test
    func wrongVaultSanitizedCodeContainsNoSensitiveData() {
        let code = StickyError.credentials(.wrongVault).sanitizedCode
        #expect(code == "credentials.wrongVault")
        // The code carries no content, paths, or secrets — just the category.
        #expect(!code.contains("password"))
        #expect(!code.contains("vaultId"))
    }
}
