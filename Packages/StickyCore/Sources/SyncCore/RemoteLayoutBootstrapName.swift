import Foundation
import Domain
import SecurityCore

// MARK: - RemoteLayout bootstrap object name (R3.4)
//
// The deterministic bootstrap object name is a pure SHA-256 function of the
// vault locator (T002/T004, plan §Bootstrap object name): the CREATE path
// uploads under exactly the name the JOIN path fetches. The hash is one-way
// and shape-identical to opaque object names — it reveals no semantic type
// and cannot be inverted to the locator (constitution VII), and never
// collides with the fixed manifest object name
// (`ManifestStore.manifestObjectName` = "manifest").
//
// R3.4 (remediation roadmap 2026-08-15, A-1): this function lived in Domain
// and forced `import CryptoKit` there, breaking the declared Foundation-only
// Domain boundary. The digest comes from `SecurityCore.SHA256DigestHash`
// (the project's single hashing surface), and the function itself moved to
// SyncCore — the module that actually consumes remote layout.

extension RemoteLayout {
    /// The deterministic remote object name for a vault's bootstrap object.
    public static func bootstrapObjectName(for locator: String) -> String {
        SHA256DigestHash.hash(Data(locator.utf8))
    }
}
