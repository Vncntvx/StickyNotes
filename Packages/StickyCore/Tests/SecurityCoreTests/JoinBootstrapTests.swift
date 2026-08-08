import Testing
import Foundation
import Domain
import SecurityCore

// MARK: - Join bootstrap verification tests (T005/T006, FR-004/FR-011)
//
// Per tasks.md T005/T006 and plan §Phase 2: verifying a FETCHED remote
// bootstrap BEFORE persisting anything. Wrong password and wrong-vault
// context fail closed with distinguishable messages and no state
// accumulation (FR-160e). Corrupt/truncated bootstraps fail closed.

@Suite struct JoinBootstrapTests {

    private func fastBootstrap(password: String = "pw") async throws -> VaultBootstrap {
        try await VaultBootstrapService.createVault(
            password: password, secretStore: InMemorySecretStore(), isTestFixture: true
        )
    }

    // MARK: - T005: wrong password at join

    @Test
    func wrongPasswordFailsClosedWithDistinguishableError() async throws {
        let bootstrap = try await fastBootstrap(password: "correct-password")

        do {
            _ = try await VaultBootstrapService.openRemoteBootstrap(
                remoteBootstrap: bootstrap,
                password: "wrong-password",
                expectedVaultId: nil
            )
            Issue.record("wrong password MUST fail closed (key-confirmation mismatch)")
        } catch StickyError.encryption(.wrongPassword) {
            #expect(true)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test
    func wrongPasswordIsDistinguishableFromVaultNotFound() async throws {
        // The two join failures must be distinguishable (CHK028): wrong
        // password is an encryption key-confirmation failure; vault-not-found
        // is a provider fetch failure. They live in different error families.
        let bootstrap = try await fastBootstrap(password: "pw")
        var wrongPasswordError: Error?
        do {
            _ = try await VaultBootstrapService.openRemoteBootstrap(
                remoteBootstrap: bootstrap, password: "nope", expectedVaultId: nil
            )
        } catch { wrongPasswordError = error }

        #expect(wrongPasswordError != nil)
        if let sticky = wrongPasswordError as? StickyError {
            let code = sticky.sanitizedCode
            #expect(code.contains("wrongPassword"), "wrong password MUST map to a distinct code (CHK028)")
            #expect(!code.contains("notFound"), "MUST NOT be conflated with vault-not-found")
        } else {
            Issue.record("wrong password MUST surface as a StickyError")
        }
    }

    @Test
    func repeatedWrongPasswordHasNoLockoutOrAccumulation() async throws {
        // FR-160e: consecutive wrong-password attempts never lock out or
        // accumulate state — every attempt is independently fail-closed.
        let bootstrap = try await fastBootstrap(password: "pw")
        for _ in 0..<5 {
            do {
                _ = try await VaultBootstrapService.openRemoteBootstrap(
                    remoteBootstrap: bootstrap, password: "wrong", expectedVaultId: nil
                )
                Issue.record("every wrong attempt MUST fail closed")
            } catch StickyError.encryption(.wrongPassword) {
                // expected — no rate limiting, no lockout
            } catch {
                Issue.record("unexpected error: \(error)")
            }
        }
    }

    // MARK: - T006: corrupt / truncated bootstrap + wrong-vault context

    @Test
    func corruptTruncatedBootstrapFailsClosed() async throws {
        // Truncated wire bytes → parse failure → fail closed.
        let bootstrap = try await fastBootstrap()
        let wire = try bootstrap.canonicalJSON()
        let truncated = wire.prefix(wire.count / 2)

        do {
            _ = try await VaultBootstrapService.openRemoteBootstrap(
                remoteBootstrap: Data(truncated),
                password: "pw",
                expectedVaultId: nil
            )
            Issue.record("truncated bootstrap MUST fail closed")
        } catch StickyError.encryption(.corruptBootstrap) {
            #expect(true)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func garbageBytesFailClosed() async throws {
        let garbage = Data("not a bootstrap at all".utf8)
        do {
            _ = try await VaultBootstrapService.openRemoteBootstrap(
                remoteBootstrap: garbage, password: "pw", expectedVaultId: nil
            )
            Issue.record("garbage bootstrap bytes MUST fail closed")
        } catch StickyError.encryption(.corruptBootstrap) {
            #expect(true)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func wrongVaultContextFailsClosed() async throws {
        // Remote bootstrap's vaultId does NOT match the locally retained
        // configuration → fail closed with the wrong-vault error.
        let remote = try await fastBootstrap()
        let localVaultId = UUID()  // a different locally-retained vault

        do {
            _ = try await VaultBootstrapService.openRemoteBootstrap(
                remoteBootstrap: remote,
                password: "pw",
                expectedVaultId: localVaultId
            )
            Issue.record("vaultId mismatch MUST fail closed (wrong-vault context)")
        } catch StickyError.credentials(.wrongVault) {
            #expect(true)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func matchingVaultContextOpensSuccessfully() async throws {
        let bootstrap = try await fastBootstrap(password: "pw")
        let key = try await VaultBootstrapService.openRemoteBootstrap(
            remoteBootstrap: bootstrap,
            password: "pw",
            expectedVaultId: bootstrap.vaultId
        )
        #expect(key.withUnsafeBytes { Data($0) }.count == 32, "master key unwrapped")
    }

    @Test
    func noVaultContextCheckWhenNoLocalConfig() async throws {
        // expectedVaultId == nil (no locally retained configuration): the
        // vault opens with the correct password without a context check.
        let bootstrap = try await fastBootstrap(password: "pw")
        let key = try await VaultBootstrapService.openRemoteBootstrap(
            remoteBootstrap: bootstrap, password: "pw", expectedVaultId: nil
        )
        #expect(key.withUnsafeBytes { Data($0) }.count == 32)
    }
}
