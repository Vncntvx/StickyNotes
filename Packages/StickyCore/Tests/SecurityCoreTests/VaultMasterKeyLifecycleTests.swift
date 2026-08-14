import Testing
import Foundation
@testable import SecurityCore

// MARK: - R1.3 Master-key persistence lifecycle (remediation roadmap 2026-08-14)

/// The audit found `createVault` unconditionally persisted the raw master
/// key under the `vault-master-key-<vaultId>` Keychain item — a copy
/// NOTHING ever read (repo-wide grep: zero readers) and NOTHING ever
/// deleted (neither `lockVault` nor `disableRememberUnlock` touched it).
/// That dead key material permanently bypasses the password: the
/// remembered-unlock item (`enableRememberUnlock` → `vault-remembered-
/// unlock-<vaultId>`) is the ONLY legitimate persisted master key, with
/// its own explicit lifecycle. Creating a vault must leave the secret
/// store untouched.
@Suite struct VaultMasterKeyLifecycleTests {

    @Test
    func createVaultPersistsNoMasterKeyOutsideRememberUnlock() async throws {
        let store = InMemorySecretStore()
        let bootstrap = try await VaultBootstrapService.createVault(
            password: "correct horse battery staple",
            secretStore: store,
            isTestFixture: true
        )

        let staleKey = "vault-master-key-\(bootstrap.vaultId.uuidString)"
        #expect(try store.load(forKey: staleKey) == nil,
                "createVault must not persist a master key that no code path reads")
    }
}
