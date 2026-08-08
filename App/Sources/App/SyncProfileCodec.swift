import Foundation
import Domain

// MARK: - SyncProfileCodec (T013/T014/T016, FR-009/FR-010)
//
// Encodes/decodes the sync-profile JSON per contracts/sync-profile-v2-delta.md
// (authoritative schema: specs/001-sticky-notes-app/contracts/
// sync-profile-export.schema.json, v2):
//
// - Contains NO secrets (Constitution VI/VII): credentials live in Keychain;
//   never exported. providerConfig carries connection info only (endpoint/
//   prefix/region/bucket) — required by the schema for the receiving device.
// - schemaVersion 2 adds optional `originDeviceName`; v1 files (schemaVersion
//   1, no originDeviceName) remain readable (Constitution IV backward
//   compatibility).
// - Unsupported versions and corrupt files fail closed (FR-010/US2/AC3).

/// A decoded sync profile (device-agnostic join information).
public struct SyncProfile: Sendable, Equatable {
    public let vaultId: UUID
    public let vaultLocator: String
    public let providerType: ProviderType
    public let providerConfig: RedactedSyncConfig
    public let encryptionSuiteVersion: Int
    /// User-readable name of the exporting device (v2, optional).
    public let originDeviceName: String?
}

public enum SyncProfileCodec {

    public static let schemaVersion = 2
    /// Accepted legacy schema version (v1 read-compat, Constitution IV).
    public static let legacySchemaVersion = 1

    /// Encodes a schema-v2 sync profile. NEVER includes credentials/keys/
    /// content — providerConfig is redacted connection info only (FR-009).
    /// Throws on serialization failure instead of silently producing an
    /// empty file (T032).
    public static func encode(
        providerType: ProviderType,
        vaultId: UUID,
        vaultLocator: String,
        providerConfig: RedactedSyncConfig,
        encryptionSuiteVersion: Int,
        originDeviceName: String?
    ) throws -> Data {
        var providerConfigJSON: [String: Any] = [
            "endpoint": providerConfig.endpoint,
        ]
        if let region = providerConfig.region { providerConfigJSON["region"] = region }
        if let bucket = providerConfig.bucket { providerConfigJSON["bucket"] = bucket }
        if let prefix = providerConfig.prefix { providerConfigJSON["prefix"] = prefix }

        var json: [String: Any] = [
            "schemaVersion": schemaVersion,
            "vaultId": vaultId.uuidString,
            "vaultLocator": vaultLocator,
            "providerType": providerType.rawValue,
            "providerConfig": providerConfigJSON,
            "encryptionSuiteVersion": encryptionSuiteVersion,
        ]
        if let originDeviceName, !originDeviceName.isEmpty {
            json["originDeviceName"] = originDeviceName
        }
        do {
            return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .prettyPrinted])
        } catch {
            throw DecodingError.invalidFile
        }
    }

    /// Decodes + validates a sync-profile file. v1 and v2 accepted;
    /// unsupported versions, corrupt files, and missing required fields
    /// throw (fail closed, FR-010/US2/AC3).
    public static func decode(_ data: Data) throws -> SyncProfile {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodingError.invalidFile
        }
        guard let schemaVersion = json["schemaVersion"] as? Int else {
            throw DecodingError.invalidFile
        }
        guard schemaVersion == Self.schemaVersion || schemaVersion == Self.legacySchemaVersion else {
            throw DecodingError.unsupportedVersion(schemaVersion)
        }

        guard let vaultIdString = json["vaultId"] as? String,
              let vaultId = UUID(uuidString: vaultIdString) else {
            throw DecodingError.invalidFile
        }
        guard let vaultLocator = json["vaultLocator"] as? String,
              !vaultLocator.isEmpty else {
            throw DecodingError.invalidFile
        }
        guard let providerTypeRaw = json["providerType"] as? String,
              let providerType = ProviderType(rawValue: providerTypeRaw) else {
            throw DecodingError.invalidFile
        }
        guard let encryptionSuiteVersion = json["encryptionSuiteVersion"] as? Int else {
            throw DecodingError.invalidFile
        }
        guard let configJSON = json["providerConfig"] as? [String: Any],
              let endpoint = configJSON["endpoint"] as? String, !endpoint.isEmpty else {
            throw DecodingError.invalidFile
        }

        let originDeviceName = json["originDeviceName"] as? String
        let providerConfig = RedactedSyncConfig(
            endpoint: endpoint,
            region: configJSON["region"] as? String,
            bucket: configJSON["bucket"] as? String,
            prefix: configJSON["prefix"] as? String
        )
        return SyncProfile(
            vaultId: vaultId,
            vaultLocator: vaultLocator,
            providerType: providerType,
            providerConfig: providerConfig,
            encryptionSuiteVersion: encryptionSuiteVersion,
            originDeviceName: originDeviceName
        )
    }

    public enum DecodingError: Error, Sendable {
        case invalidFile
        case unsupportedVersion(Int)

        public var sanitizedCode: String {
            switch self {
            case .invalidFile: return "syncProfile.invalidFile"
            case .unsupportedVersion: return "syncProfile.unsupportedVersion"
            }
        }
    }
}
