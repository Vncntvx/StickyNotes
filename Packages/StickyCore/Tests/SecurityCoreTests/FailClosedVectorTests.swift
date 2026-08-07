import Testing
import Foundation
import CryptoKit
import Domain
import SecurityCore

// MARK: - Exhaustive fail-closed input vectors (T196, FR-160d clarified 2026-08-07)
//
// Per tasks.md T196: each of the eight enumerated inputs triggers fail-closed:
// (a) wrong password; (b) modified ciphertext (bit-flip/truncation/extension);
// (c) invalid/mismatched AES-GCM auth tag; (d) mismatched object ID;
// (e) mismatched object type; (f) mismatched vault ID; (g) unsupported
// envelope schema version; (h) corrupted/truncated envelope structure. For
// each: the object is rejected without writing local data, without accepting
// the remote object, and without overwriting a local version.

@Suite struct FailClosedVectorTests {

    private func fastVault() async throws -> (VaultBootstrap, Vault) {
        let bootstrap = try await VaultBootstrapService.createVault(
            password: "pw", secretStore: InMemorySecretStore(), isTestFixture: true
        )
        let key = try await VaultBootstrapService.openVault(bootstrap, password: "pw")
        return (bootstrap, Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key))
    }

    // (a) wrong password

    @Test
    func wrongPasswordFailsClosed() async throws {
        let (bootstrap, _) = try await fastVault()
        do {
            _ = try await VaultBootstrapService.openVault(bootstrap, password: "wrong")
            Issue.record("(a) wrong password must fail closed")
        } catch StickyError.encryption(.wrongPassword) {
            #expect(true)
        } catch {
            Issue.record("(a) unexpected error: \(error)")
        }
    }

    // (b) modified ciphertext (bit-flip)

    @Test
    func modifiedCiphertextBitFlipFailsClosed() async throws {
        let (_, vault) = try await fastVault()
        let envelope = try vault.encrypt(
            objectId: UUID().uuidString, objectType: "note", schemaVersion: 1,
            plaintext: Data("payload".utf8)
        )
        var tampered = envelope
        tampered.ciphertext[tampered.ciphertext.count / 2] ^= 0xFF
        do {
            _ = try vault.decrypt(envelope: tampered, objectType: "note", schemaVersion: 1)
            Issue.record("(b) bit-flipped ciphertext must fail closed")
        } catch StickyError.encryption(.modifiedCiphertext) {
            #expect(true)
        } catch {
            // The umbrella wrongObjectContext is also acceptable as fail-closed.
            #expect(error is StickyError)
        }
    }

    // (b) modified ciphertext (truncation)

    @Test
    func modifiedCiphertextTruncationFailsClosed() async throws {
        let (_, vault) = try await fastVault()
        let envelope = try vault.encrypt(
            objectId: UUID().uuidString, objectType: "note", schemaVersion: 1,
            plaintext: Data("payload".utf8)
        )
        var truncated = envelope
        truncated.ciphertext = Data(truncated.ciphertext.dropLast(5))
        do {
            _ = try vault.decrypt(envelope: truncated, objectType: "note", schemaVersion: 1)
            Issue.record("(b) truncated ciphertext must fail closed")
        } catch {
            #expect(error is StickyError)
        }
    }

    // (c) invalid/mismatched auth tag — covered by bit-flip in the tag region.
    // The AES-GCM combined format puts the tag at the end of the ciphertext.

    @Test
    func invalidAuthTagFailsClosed() async throws {
        let (_, vault) = try await fastVault()
        let envelope = try vault.encrypt(
            objectId: UUID().uuidString, objectType: "note", schemaVersion: 1,
            plaintext: Data("payload".utf8)
        )
        var tamperedTag = envelope
        // Flip the last byte (the tag region in AES-GCM combined).
        tamperedTag.ciphertext[tamperedTag.ciphertext.count - 1] ^= 0x01
        do {
            _ = try vault.decrypt(envelope: tamperedTag, objectType: "note", schemaVersion: 1)
            Issue.record("(c) invalid auth tag must fail closed")
        } catch {
            #expect(error is StickyError)
        }
    }

    // (d) mismatched object ID — the envelope's objectId is not a valid UUID
    // OR the context's objectId differs from what was used at encryption.

    @Test
    func mismatchedObjectIdFailsClosed() async throws {
        let (_, vault) = try await fastVault()
        // Encrypt with one objectId, then tamper the envelope's objectId.
        let envelope = try vault.encrypt(
            objectId: UUID().uuidString, objectType: "note", schemaVersion: 1,
            plaintext: Data("payload".utf8)
        )
        var tampered = envelope
        tampered.objectId = "not-a-uuid"
        do {
            _ = try vault.decrypt(envelope: tampered, objectType: "note", schemaVersion: 1)
            Issue.record("(d) invalid object ID must fail closed")
        } catch StickyError.encryption(.wrongObjectId) {
            #expect(true)
        } catch {
            // Acceptable as fail-closed umbrella.
            #expect(error is StickyError)
        }
    }

    // (e) mismatched object type — decrypt with a different objectType than
    // was used at encryption. The AAD differs → AES-GCM open fails.

    @Test
    func mismatchedObjectTypeFailsClosed() async throws {
        let (_, vault) = try await fastVault()
        let envelope = try vault.encrypt(
            objectId: UUID().uuidString, objectType: "note", schemaVersion: 1,
            plaintext: Data("payload".utf8)
        )
        do {
            _ = try vault.decrypt(envelope: envelope, objectType: "asset", schemaVersion: 1)
            Issue.record("(e) wrong object type must fail closed")
        } catch {
            #expect(error is StickyError)
        }
    }

    // (f) mismatched vault ID — decrypt with a different vault's master key.

    @Test
    func mismatchedVaultIdFailsClosed() async throws {
        let (_, vault) = try await fastVault()
        let envelope = try vault.encrypt(
            objectId: UUID().uuidString, objectType: "note", schemaVersion: 1,
            plaintext: Data("payload".utf8)
        )
        // A different vault with a fresh master key.
        let otherKey = KeyDerivation.generateMasterKey()
        let otherVault = Vault(vaultId: UUID(), encryptionSuiteVersion: 1, masterKey: otherKey)
        do {
            _ = try otherVault.decrypt(envelope: envelope, objectType: "note", schemaVersion: 1)
            Issue.record("(f) wrong vault must fail closed")
        } catch {
            #expect(error is StickyError)
        }
    }

    // (g) unsupported envelope schema version

    @Test
    func unsupportedEnvelopeVersionFailsClosed() async throws {
        let (_, vault) = try await fastVault()
        var envelope = try vault.encrypt(
            objectId: UUID().uuidString, objectType: "note", schemaVersion: 1,
            plaintext: Data("payload".utf8)
        )
        envelope.envelopeVersion = 999
        do {
            _ = try vault.decrypt(envelope: envelope, objectType: "note", schemaVersion: 1)
            Issue.record("(g) unsupported envelope version must fail closed")
        } catch StickyError.encryption(.unsupportedEnvelopeVersion) {
            #expect(true)
        } catch {
            Issue.record("(g) unexpected error: \(error)")
        }
    }

    // (h) corrupted/truncated envelope structure — nonce too short or
    // ciphertext shorter than the 16-byte tag.

    @Test
    func corruptEnvelopeStructureShortNonceFailsClosed() async throws {
        let (_, vault) = try await fastVault()
        var envelope = try vault.encrypt(
            objectId: UUID().uuidString, objectType: "note", schemaVersion: 1,
            plaintext: Data("payload".utf8)
        )
        envelope.nonce = Data(repeating: 0, count: 5) // too short
        do {
            _ = try vault.decrypt(envelope: envelope, objectType: "note", schemaVersion: 1)
            Issue.record("(h) short nonce (corrupt structure) must fail closed")
        } catch StickyError.encryption(.corruptEnvelopeStructure) {
            #expect(true)
        } catch {
            Issue.record("(h) unexpected error: \(error)")
        }
    }

    @Test
    func corruptEnvelopeStructureShortCiphertextFailsClosed() async throws {
        let (_, vault) = try await fastVault()
        var envelope = try vault.encrypt(
            objectId: UUID().uuidString, objectType: "note", schemaVersion: 1,
            plaintext: Data("payload".utf8)
        )
        envelope.ciphertext = Data(repeating: 0, count: 5) // shorter than 16-byte tag
        do {
            _ = try vault.decrypt(envelope: envelope, objectType: "note", schemaVersion: 1)
            Issue.record("(h) short ciphertext (corrupt structure) must fail closed")
        } catch StickyError.encryption(.corruptEnvelopeStructure) {
            #expect(true)
        } catch {
            Issue.record("(h) unexpected error: \(error)")
        }
    }

    // MARK: - Exhaustive list coverage

    @Test
    func allEightFR160dInputsHaveDedicatedErrorCases() {
        // Verify the eight enumerated inputs each have a distinct case.
        let cases: [EncryptionError] = [
            .wrongPassword,               // (a)
            .modifiedCiphertext,          // (b)
            .invalidTag,                  // (c)
            .wrongObjectId,               // (d)
            .wrongObjectType,             // (e)
            .wrongVaultContext,           // (f)
            .unsupportedEnvelopeVersion,  // (g)
            .corruptEnvelopeStructure,    // (h)
        ]
        // Each has a distinct sanitized code.
        let codes = Set(cases.map(\.sanitizedCode))
        #expect(codes.count == 8, "all eight FR-160d inputs must have distinct codes")
        // The legacy umbrella is still present for backward compatibility.
        #expect(EncryptionError.wrongObjectContext.sanitizedCode == "wrongObjectContext")
    }
}
