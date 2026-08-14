import Testing
import Foundation
import Domain
import SecurityCore

// MARK: - Argon2id production minimum tests (T195, FR-160c clarified 2026-08-07)
//
// Per tasks.md T195: production vault bootstrapping rejects parameter sets
// weaker than memory ≥ 19456 KiB (19 MiB), iterations ≥ 2, parallelism ≥ 1.
// The schema minimums (8/1/1) are accepted ONLY for test fixtures. Parameter
// values used at vault creation are stored alongside the wrapped master key
// so future unlocks reproduce the derivation exactly.

@Suite struct Argon2idProductionMinimumTests {

    /// Deterministic non-empty salt (the production guard now rejects empty salts).
    private static let testSalt = Data(repeating: 0xAB, count: 16)

    @Test
    func productionMinimumConstantsMatchFR160c() {
        #expect(Argon2Parameters.productionMinimumMemoryKiB == 19_456)
        #expect(Argon2Parameters.productionMinimumIterations == 2)
        #expect(Argon2Parameters.productionMinimumParallelism == 1)
    }

    @Test
    func recommendedParametersExceedProductionMinimum() {
        #expect(Argon2Parameters.recommended.meetsProductionMinimum)
        // 64 MiB / 3 / 4 all exceed the 19 MiB / 2 / 1 minimums.
        #expect(Argon2Parameters.recommended.memoryKiB == 65_536)
        #expect(Argon2Parameters.recommended.iterations == 3)
        #expect(Argon2Parameters.recommended.parallelism == 4)
    }

    // MARK: - Weak memory rejected

    @Test
    func weakMemoryRejectedInProductionContext() {
        let weak = Argon2Parameters(salt: Self.testSalt, memoryKiB: 8, iterations: 2, parallelism: 1)
        #expect(!weak.meetsProductionMinimum)
        do {
            try weak.requireProductionMinimum(isTestFixture: false)
            Issue.record("weak memory must be rejected in production context")
        } catch StickyError.encryption(.kdfFailed) {
            #expect(Bool(true))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func memoryExactlyAtMinimumIsAccepted() {
        let atMin = Argon2Parameters(salt: Self.testSalt, memoryKiB: 19_456, iterations: 2, parallelism: 1)
        #expect(atMin.meetsProductionMinimum)
        #expect(throws: Never.self) {
            try atMin.requireProductionMinimum(isTestFixture: false)
        }
    }

    @Test
    func memoryBelowMinimumRejected() {
        let below = Argon2Parameters(salt: Self.testSalt, memoryKiB: 19_455, iterations: 2, parallelism: 1)
        #expect(!below.meetsProductionMinimum)
    }

    // MARK: - Weak iterations rejected

    @Test
    func weakIterationsRejectedInProductionContext() {
        let weak = Argon2Parameters(salt: Self.testSalt, memoryKiB: 19_456, iterations: 1, parallelism: 1)
        #expect(!weak.meetsProductionMinimum)
        do {
            try weak.requireProductionMinimum(isTestFixture: false)
            Issue.record("weak iterations must be rejected in production context")
        } catch StickyError.encryption(.kdfFailed) {
            #expect(Bool(true))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    // MARK: - Weak parallelism rejected

    @Test
    func weakParallelismRejectedInProductionContext() {
        let weak = Argon2Parameters(salt: Self.testSalt, memoryKiB: 19_456, iterations: 2, parallelism: 0)
        #expect(!weak.meetsProductionMinimum)
    }

    // MARK: - Test-fixture bypass

    @Test
    func testFixtureBypassAcceptsWeakParameters() {
        let weak = Argon2Parameters(salt: Self.testSalt, memoryKiB: 8, iterations: 1, parallelism: 1)
        #expect(!weak.meetsProductionMinimum)
        #expect(throws: Never.self) {
            try weak.requireProductionMinimum(isTestFixture: true)
        }
    }

    // MARK: - createVault enforces the guard

    @Test
    func createVaultWithProductionParametersSucceeds() async throws {
        // With isTestFixture=true, fast params (64 KiB) are used and the
        // production-minimum guard is bypassed. The stored params do NOT
        // meet the production minimum — they're test-fixture params.
        let bootstrap = try await VaultBootstrapService.createVault(
            password: "pw", secretStore: InMemorySecretStore(), isTestFixture: true
        )
        #expect(!bootstrap.argon2id.meetsProductionMinimum, "test-fixture params are below production minimum")
        // The bootstrap still records the params used (so future unlocks
        // reproduce the derivation exactly).
        #expect(bootstrap.argon2id.memoryKiB == 64)
        #expect(bootstrap.argon2id.iterations == 2)
        #expect(bootstrap.argon2id.parallelism == 2)
    }

    @Test
    func bootstrapRecordsArgon2idParametersForFutureUnlocks() async throws {
        // The parameters used at vault creation are stored in the bootstrap
        // so future unlocks reproduce the derivation exactly (FR-160c).
        let bootstrap = try await VaultBootstrapService.createVault(
            password: "pw", secretStore: InMemorySecretStore(), isTestFixture: true
        )
        // Test-fixture params (fast).
        #expect(bootstrap.argon2id.memoryKiB == 64)
        #expect(bootstrap.argon2id.iterations == 2)
        #expect(bootstrap.argon2id.parallelism == 2)
        #expect(!bootstrap.argon2id.salt.isEmpty)
        // Unlocking with the stored params + correct password succeeds.
        let key = try await VaultBootstrapService.openVault(bootstrap, password: "pw")
        #expect(key.withUnsafeBytes { Data($0) }.count == 32)
    }

    // MARK: - R1.5 Empty-salt guard (remediation roadmap 2026-08-14)

    /// `Argon2Parameters.recommended` ships with an EMPTY salt (a
    /// registration-time oversight the audit flagged): any caller deriving
    /// a KEK straight from it gets a deterministic derivation. The
    /// production guard must reject empty salts so the template cannot be
    /// consumed as-is.
    @Test
    func productionMinimumRejectsEmptySalt() {
        #expect(Argon2Parameters.recommended.salt.isEmpty,
                "precondition: the audit found the recommended template with an empty salt")
        do {
            try Argon2Parameters.recommended.requireProductionMinimum(isTestFixture: false)
            Issue.record("empty salt must be rejected in production context")
        } catch StickyError.encryption(.kdfFailed) {
            #expect(Bool(true))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
