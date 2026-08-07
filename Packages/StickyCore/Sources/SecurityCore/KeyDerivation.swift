import Foundation
import CryptoKit
import Security
import Domain
import SwiftArgon2

// MARK: - KeyDerivation (T111/T112)
//
// Argon2id KEK derivation from the sync password (memory-hard — the KEK
// must NOT come from a fast KDF; research.md R9). Parameter + salt stored in
// the vault bootstrap so the same password re-derives the same KEK on any
// device.

/// Argon2id parameters recorded in the vault bootstrap. 64 MiB, 3 iterations,
/// 4 lanes — the OWASP-recommended minimum, verified in Milestone 0
/// (Prototypes/Argon2idPrototype, m=65536/t=3/p=4).
public struct Argon2Parameters: Sendable, Equatable, Codable {
    public var salt: Data
    public var memoryKiB: Int
    public var iterations: Int
    public var parallelism: Int

    public init(salt: Data, memoryKiB: Int = 65536, iterations: Int = 3, parallelism: Int = 4) {
        self.salt = salt
        self.memoryKiB = memoryKiB
        self.iterations = iterations
        self.parallelism = parallelism
    }

    /// OWASP-recommended defaults (m=64MiB, t=3, p=4).
    public static let recommended = Argon2Parameters(
        salt: Data(),
        memoryKiB: 65536,
        iterations: 3,
        parallelism: 4
    )
}

// MARK: - Argon2id production minimums (FR-160c, clarified 2026-08-07)
//
// Production vault bootstrapping MUST reject parameter sets weaker than:
// memory ≥ 19456 KiB (19 MiB), iterations ≥ 2, parallelism ≥ 1 (OWASP
// guidance). The schema minimums (8/1/1) exist ONLY to permit deterministic
// unit-test fixtures that exercise envelope parsing without paying the full
// derivation cost. The rejection guard is explicit so a future caller cannot
// accidentally use weaker params.

public extension Argon2Parameters {

    /// The production minimum memory cost (19 MiB / 19456 KiB).
    static let productionMinimumMemoryKiB = 19_456
    /// The production minimum iteration count.
    static let productionMinimumIterations = 2
    /// The production minimum parallelism (lanes).
    static let productionMinimumParallelism = 1

    /// Returns `true` if these parameters meet or exceed the FR-160c
    /// production minimums.
    var meetsProductionMinimum: Bool {
        memoryKiB >= Self.productionMinimumMemoryKiB
            && iterations >= Self.productionMinimumIterations
            && parallelism >= Self.productionMinimumParallelism
    }

    /// Asserts that these parameters meet the FR-160c production minimums.
    /// Throws `.encryption(.kdfFailed)` if any parameter is weaker than the
    /// minimum. Use this in the production vault-bootstrap path so a future
    /// caller cannot accidentally use test-fixture parameters.
    ///
    /// - Parameter isTestFixture: When `true`, the guard is skipped (test
    ///   fixtures may use the weaker schema minimums 8/1/1 to keep the
    ///   suite fast). Production callers MUST pass `false`.
    func requireProductionMinimum(isTestFixture: Bool = false) throws {
        if isTestFixture { return }
        guard meetsProductionMinimum else {
            throw StickyError.encryption(.kdfFailed)
        }
    }
}

/// Derives the key-encryption key (KEK) from the sync password using
/// Argon2id. Runs off the main actor by design (memory-hard; minutes-scale
/// work for attackers, seconds for us).
public enum KeyDerivation {

    /// Derives a 32-byte KEK. Throws `.encryption(.kdfFailed)` on any error.
    public static func deriveKEK(
        password: String,
        parameters: Argon2Parameters
    ) async throws -> SymmetricKey {
        let argon2: Argon2
        do {
            argon2 = try Argon2(params: Argon2Params(
                parallelism: UInt32(parameters.parallelism),
                tagLength: 32,
                memorySize: UInt32(parameters.memoryKiB),
                iterations: UInt32(parameters.iterations),
                variant: .argon2id
            ))
        } catch {
            throw StickyError.encryption(.kdfFailed)
        }
        do {
            let kekBytes = try await argon2.compute(
                password: Data(password.utf8),
                salt: parameters.salt
            )
            return SymmetricKey(data: kekBytes)
        } catch {
            throw StickyError.encryption(.kdfFailed)
        }
    }

    /// Generates a fresh random salt (16 bytes).
    public static func generateSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    /// Generates a fresh random vault master key (32 bytes).
    public static func generateMasterKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }
}
