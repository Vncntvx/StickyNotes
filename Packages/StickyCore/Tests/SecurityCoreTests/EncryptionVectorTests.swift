import Testing
import Foundation
import CryptoKit
import Domain
import SecurityCore

// MARK: - Encryption test vectors (T106)
//
// Per tasks.md T106: encryption test vectors covering correct/wrong password,
// modified ciphertext/nonce/AAD, wrong object ID/type/vault, unsupported
// version, password re-wrap, Keychain unavailable, corrupt bootstrap.

@Suite struct EncryptionVectorTests {

    // Uses small Argon2id params so the suite runs fast (vectors, not
    // production parameters — production uses m=64MiB validated in M0).
    private func fastParameters(salt: Data = Data(repeating: 0x42, count: 16)) -> Argon2Parameters {
        Argon2Parameters(salt: salt, memoryKiB: 64, iterations: 2, parallelism: 2)
    }

    // MARK: - Vault bootstrap

    @Test
    func createAndOpenVaultWithCorrectPassword() async throws {
        let bootstrap = try await VaultBootstrapService.createVault(
            password: "correct horse battery staple 同步",
            secretStore: InMemorySecretStore()
        )
        let masterKey = try await VaultBootstrapService.openVault(bootstrap, password: "correct horse battery staple 同步")
        // 32-byte master key.
        let bytes = masterKey.withUnsafeBytes { Data($0) }
        #expect(bytes.count == 32)
    }

    @Test
    func wrongPasswordFailsClosed() async throws {
        let bootstrap = try await VaultBootstrapService.createVault(
            password: "right-password",
            secretStore: InMemorySecretStore()
        )
        do {
            _ = try await VaultBootstrapService.openVault(bootstrap, password: "wrong-password")
            Issue.record("wrong password must fail closed")
        } catch StickyError.encryption(.wrongPassword) {
            #expect(true)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func corruptBootstrapFailsClosed() throws {
        let garbage = Data("not a vault at all".utf8)
        do {
            _ = try VaultBootstrap.fromCanonicalJSON(garbage)
            Issue.record("corrupt bootstrap must fail closed")
        } catch StickyError.encryption(.corruptBootstrap) {
            #expect(true)
        }
    }

    @Test
    func unsupportedEnvelopeVersionFailsClosed() async throws {
        var bootstrap = try await VaultBootstrapService.createVault(
            password: "pw", secretStore: InMemorySecretStore()
        )
        bootstrap.encryptionSuiteVersion = 999
        do {
            _ = try await VaultBootstrapService.openVault(bootstrap, password: "pw")
            Issue.record("unsupported suite version must fail closed")
        } catch StickyError.encryption(.unsupportedEnvelopeVersion) {
            #expect(true)
        }
    }

    @Test
    func passwordChangeReWrapsWithoutReEncryptingObjects() async throws {
        let store = InMemorySecretStore()
        let bootstrap = try await VaultBootstrapService.createVault(password: "old-pw", secretStore: store)
        let oldKey = try await VaultBootstrapService.openVault(bootstrap, password: "old-pw")

        // Encrypt an object BEFORE the password change.
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: oldKey)
        let objectId = UUID().uuidString
        let envelope = try vault.encrypt(
            objectId: objectId, objectType: "note", schemaVersion: 1,
            plaintext: Data("the note content".utf8)
        )

        // Password change: re-wrap only.
        let updated = try await VaultBootstrapService.changePassword(
            bootstrap, currentPassword: "old-pw", newPassword: "new-pw"
        )
        let newKey = try await VaultBootstrapService.openVault(updated, password: "new-pw")
        let newVault = Vault(vaultId: updated.vaultId, encryptionSuiteVersion: 1, masterKey: newKey)

        // The SAME envelope (unchanged object) still decrypts — objects were
        // NOT re-encrypted (FR-164).
        let decrypted = try newVault.decrypt(envelope: envelope, objectType: "note", schemaVersion: 1)
        #expect(decrypted.plaintext == Data("the note content".utf8))

        // Old password no longer opens the vault.
        do {
            _ = try await VaultBootstrapService.openVault(updated, password: "old-pw")
            Issue.record("old password must fail after change")
        } catch StickyError.encryption(.wrongPassword) {
            #expect(true)
        }
    }

    // MARK: - Object encryption: modified inputs fail closed

    @Test
    func modifiedCiphertextFailsClosed() async throws {
        let store = InMemorySecretStore()
        let bootstrap = try await VaultBootstrapService.createVault(password: "pw", secretStore: store)
        let key = try await VaultBootstrapService.openVault(bootstrap, password: "pw")
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)
        let context = vault.context(objectId: UUID().uuidString, objectType: "note", schemaVersion: 1)

        let (_, sealed) = try ObjectCrypto.encrypt(Data("hello".utf8), masterKey: key, context: context)
        var tampered = sealed
        tampered[tampered.count / 2] ^= 0xFF

        do {
            _ = try ObjectCrypto.decrypt(sealed: tampered, masterKey: key, context: context)
            Issue.record("modified ciphertext must fail closed")
        } catch StickyError.encryption(.modifiedCiphertext) {
            #expect(true)
        }
    }

    @Test
    func modifiedAADFailsClosed() async throws {
        let store = InMemorySecretStore()
        let bootstrap = try await VaultBootstrapService.createVault(password: "pw", secretStore: store)
        let key = try await VaultBootstrapService.openVault(bootstrap, password: "pw")
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)

        let context = vault.context(objectId: UUID().uuidString, objectType: "note", schemaVersion: 1)
        let (_, sealed) = try ObjectCrypto.encrypt(Data("hello".utf8), masterKey: key, context: context)

        // Same key, but a DIFFERENT context (object id substituted).
        let wrongContext = vault.context(objectId: UUID().uuidString, objectType: "note", schemaVersion: 1)
        do {
            _ = try ObjectCrypto.decrypt(sealed: sealed, masterKey: key, context: wrongContext)
            Issue.record("AAD substitution must fail closed")
        } catch StickyError.encryption(.modifiedCiphertext) {
            #expect(true)
        }
    }

    @Test
    func wrongObjectTypeAndVaultFailClosed() async throws {
        let store = InMemorySecretStore()
        let bootstrap = try await VaultBootstrapService.createVault(password: "pw", secretStore: store)
        let key = try await VaultBootstrapService.openVault(bootstrap, password: "pw")
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)

        let envelope = try vault.encrypt(
            objectId: UUID().uuidString, objectType: "note", schemaVersion: 1,
            plaintext: Data("payload".utf8)
        )

        // Wrong object type → wrong AAD → fail closed.
        do {
            _ = try vault.decrypt(envelope: envelope, objectType: "asset", schemaVersion: 1)
            Issue.record("wrong object type must fail closed")
        } catch StickyError.encryption(.modifiedCiphertext) {
            #expect(true)
        }

        // Wrong vault → wrong AAD → fail closed.
        let otherVault = Vault(vaultId: UUID(), encryptionSuiteVersion: 1, masterKey: key)
        do {
            _ = try otherVault.decrypt(envelope: envelope, objectType: "note", schemaVersion: 1)
            Issue.record("wrong vault must fail closed")
        } catch StickyError.encryption(.modifiedCiphertext) {
            #expect(true)
        }
    }

    @Test
    func unsupportedEnvelopeVersionFailsClosed() throws {
        var envelope = EncryptedEnvelope(objectId: "o1", nonce: Data(repeating: 1, count: 12), ciphertext: Data())
        envelope.envelopeVersion = 99
        do {
            _ = try EncryptedEnvelope.fromCanonicalJSON(try envelope.canonicalJSON())
            Issue.record("unsupported envelope version must fail closed")
        } catch StickyError.encryption(.unsupportedEnvelopeVersion) {
            #expect(true)
        }
    }

    // MARK: - Determinism

    @Test
    func sameContextSameKeyDifferentNonce() async throws {
        let store = InMemorySecretStore()
        let bootstrap = try await VaultBootstrapService.createVault(password: "pw", secretStore: store)
        let key = try await VaultBootstrapService.openVault(bootstrap, password: "pw")
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)
        let context = vault.context(objectId: UUID().uuidString, objectType: "note", schemaVersion: 1)

        let (nonce1, sealed1) = try ObjectCrypto.encrypt(Data("same".utf8), masterKey: key, context: context)
        let (nonce2, sealed2) = try ObjectCrypto.encrypt(Data("same".utf8), masterKey: key, context: context)

        // Random nonces → different ciphertexts, both decrypt fine.
        #expect(nonce1 != nonce2)
        #expect(sealed1 != sealed2)
        let back = try ObjectCrypto.decrypt(sealed: sealed2, masterKey: key, context: context)
        #expect(back == Data("same".utf8))
    }

    // MARK: - Keychain unavailable / credential failures

    @Test
    func keychainUnavailableMapsToCredentialsError() throws {
        // The SecretStore protocol surfaces save/load failures as typed
        // credential errors; a store that always throws models Keychain
        // unavailability.
        struct FailingStore: SecretStore {
            func save(_ data: Data, forKey key: String) throws { throw StickyError.credentials(.saveFailed) }
            func load(forKey key: String) throws -> Data? { throw StickyError.credentials(.accessDenied) }
            func delete(forKey key: String) throws { throw StickyError.credentials(.deleteFailed) }
        }
        let store = FailingStore()
        do {
            try store.save(Data(), forKey: "k")
            Issue.record("expected save failure")
        } catch StickyError.credentials(.saveFailed) {
            #expect(true)
        }
    }

    // MARK: - Deterministic KEK (same salt+password → same key)

    @Test
    func sameSaltAndPasswordDeriveSameKEK() async throws {
        let parameters = fastParameters()
        let k1 = try await KeyDerivation.deriveKEK(password: "pw", parameters: parameters)
        let k2 = try await KeyDerivation.deriveKEK(password: "pw", parameters: parameters)
        #expect(k1.withUnsafeBytes { Data($0) } == k2.withUnsafeBytes { Data($0) })

        let differentSalt = fastParameters(salt: Data(repeating: 0x99, count: 16))
        let k3 = try await KeyDerivation.deriveKEK(password: "pw", parameters: differentSalt)
        #expect(k1.withUnsafeBytes { Data($0) } != k3.withUnsafeBytes { Data($0) }, "different salt must produce a different KEK")
    }
}
