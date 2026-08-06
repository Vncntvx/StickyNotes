import Foundation
import Domain
import SecurityCore

// MARK: - ManifestStore (T118)
//
// Per tasks.md T118 and contracts/encrypted-manifest.schema.json:
//
// - The remote manifest is the SINGLE serialization point (research.md R12).
// - Committed via a conditional write (`If-Match`). On precondition failure
//   the engine re-fetches, re-applies the update, and retries (bounded).
// - The manifest is itself an encrypted object (encrypted-envelope.schema.json).
// - Fail closed: a corrupt/unsupported manifest is never silently accepted
//   and never overwrites local state.

/// The outcome of a conditional manifest commit. `created` means the
/// manifest was written for the first time (no prior version existed);
/// `replaced` means an existing manifest was conditionally replaced.
public enum ManifestCommitOutcome: Sendable, Equatable {
    case created
    case replaced
}

/// Handles fetch/decrypt + conditional-commit of the remote manifest.
public actor ManifestStore {
    /// Maximum conditional-commit retries after precondition failure
    /// (research.md R12: bounded).
    public static let maxConditionalRetries = 5

    private let provider: any SyncProviderProtocol
    private let vault: Vault

    public init(provider: any SyncProviderProtocol, vault: Vault) {
        self.provider = provider
        self.vault = vault
    }

    /// The manifest's fixed opaque remote object name (single serialization
    /// point).
    public static let manifestObjectName = "manifest"

    // MARK: - Fetch

    /// Fetches + decrypts + validates the remote manifest.
    /// - Returns: `nil` when the manifest does not exist yet (first sync).
    /// - Throws: `.remoteCorruption(.manifestInvalid)` for corrupt manifests
    ///   (fail closed); `.encryption(.wrongObjectContext)` for substituted
    ///   manifests.
    public func fetch() async throws -> RemoteManifest? {
        let result: ManifestFetchResult
        do {
            result = try await provider.fetchManifest()
        } catch ProviderError.notFound {
            return nil
        }
        let envelope = try EncryptedEnvelope.fromCanonicalJSON(result.data)
        let decrypted = try vault.decrypt(
            envelope: envelope,
            objectType: "manifest",
            schemaVersion: RemoteManifest.schemaVersion
        )
        guard let manifest = try? CanonicalJSONDecoder().decode(RemoteManifest.self, from: decrypted.plaintext) else {
            throw StickyError.remoteCorruption(.manifestInvalid)
        }
        guard manifest.schemaVersion == RemoteManifest.schemaVersion else {
            throw StickyError.remoteCorruption(.manifestInvalid)
        }
        // Fail closed on vault substitution: the manifest's vaultId must be
        // ours (defense in depth — the envelope AAD already binds it).
        guard manifest.vaultId == vault.vaultId else {
            throw StickyError.encryption(.wrongObjectContext)
        }
        return manifest
    }

    /// The manifest's current version token (for conditional ops). `nil`
    /// when the manifest does not exist.
    public func currentVersionToken() async throws -> String? {
        let metadata = try await provider.fetchMetadata(objectName: Self.manifestObjectName)
        return metadata?.versionToken
    }

    // MARK: - Commit

    /// Commits an updated manifest conditionally. `builder` is a pure
    /// function of the fetched manifest — on precondition failure the loop
    /// re-fetches and re-applies it (bounded by `maxConditionalRetries`).
    ///
    /// - Parameters:
    ///   - deviceId: The modifying device (manifest `updatedByDeviceId`).
    ///   - builder: Given the current remote manifest (nil = absent), build
    ///     the next manifest + produce the new opaque version token.
    /// - Returns: `.created` when the manifest was written for the first
    ///   time, `.replaced` when an existing manifest was conditionally
    ///   replaced.
    public func commit(
        deviceId: UUID,
        builder: @Sendable (RemoteManifest?) async throws -> (manifest: RemoteManifest, versionToken: String)
    ) async throws -> ManifestCommitOutcome {
        var attempt = 0
        while attempt < Self.maxConditionalRetries {
            let current = try await fetch()
            let token = try await currentVersionToken()
            let (next, newToken) = try await builder(current)

            var candidate = next
            candidate.manifestVersion = newToken
            candidate.updatedAt = Date()
            candidate.updatedByDeviceId = deviceId

            let payload = try CanonicalJSONEncoder().encode(candidate)
            // The manifest's envelope uses the vault ID as its object ID —
            // a stable UUID binding the manifest to this vault (AAD).
            let envelope = try vault.encrypt(
                objectId: vault.vaultId.uuidString,
                objectType: "manifest",
                schemaVersion: RemoteManifest.schemaVersion,
                plaintext: payload
            )
            let wire = try envelope.canonicalJSON()

            do {
                if let token {
                    try await provider.replaceManifest(data: wire, ifMatch: token)
                    return .replaced
                } else {
                    // Conditional create. A concurrent committer may create
                    // the manifest between our fetch and upload; the
                    // provider's `If-None-Match: *` semantics surface that
                    // as `.conditionalFailed`, and we retry (bounded).
                    try await provider.upload(objectName: Self.manifestObjectName, data: wire)
                    return .created
                }
            } catch ProviderError.conditionalFailed {
                // Precondition failure: someone else committed. Re-fetch and
                // re-apply (bounded).
                attempt += 1
                continue
            }
        }
        throw StickyError.syncConflict(.manifestPreconditionFailed)
    }
}
