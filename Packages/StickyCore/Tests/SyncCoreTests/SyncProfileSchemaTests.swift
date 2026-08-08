import Testing
import Foundation

// MARK: - Sync-profile schema v2 contract tests (T001, FR-009/FR-010)
//
// Per tasks.md T001 and contracts/sync-profile-v2-delta.md:
// - A v1 file (schemaVersion 1, no originDeviceName) MUST validate under the
//   v2 validator (backward compatible, Constitution IV).
// - A v2 file with `originDeviceName` round-trips through the validator.
// - A file with an unsupported schemaVersion (0 / 3) MUST fail validation
//   (fail closed, FR-010).
//
// The validator under test is the DOCUMENTED contract semantics: required
// fields, additionalProperties:false strictness, providerConfig redaction
// requirements, and the version const. The JSON Schema file is loaded from
// specs/001-sticky-notes-app/contracts/sync-profile-export.schema.json (the
// authoritative artifact T003 bumps to v2).

@Suite struct SyncProfileSchemaTests {

    /// Repo-relative path to the authoritative schema artifact.
    private static var schemaURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SyncCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // StickyCore
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("specs/001-sticky-notes-app/contracts/sync-profile-export.schema.json")
    }

    private static var schema: [String: Any] {
        get throws {
            let data = try Data(contentsOf: schemaURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw TestError.schemaUnreadable
            }
            return json
        }
    }

    enum TestError: Error {
        case schemaUnreadable
        case schemaNotV2
        case profileUnreadable
    }

    /// A minimal sync-profile-export v2 validator implementing the contract
    /// semantics of the schema file (const/required/additionalProperties).
    static func validate(_ profile: [String: Any], against schema: [String: Any]) -> Bool {
        guard let properties = schema["properties"] as? [String: Any] else { return false }
        guard let required = schema["required"] as? [String] else { return false }

        // required fields present
        for key in required where profile[key] == nil {
            return false
        }
        // additionalProperties: false
        if (schema["additionalProperties"] as? Bool) == false {
            for key in profile.keys where properties[key] == nil {
                return false
            }
        }
        // schemaVersion enum (v1 + v2 accepted; anything else rejected)
        if let versionProp = properties["schemaVersion"] as? [String: Any],
           let accepted = versionProp["enum"] as? [Int] {
            guard let value = profile["schemaVersion"] as? Int else { return false }
            if !accepted.contains(value) { return false }
        }
        // providerType enum
        if let typeProp = properties["providerType"] as? [String: Any],
           let enumValues = typeProp["enum"] as? [String],
           let value = profile["providerType"] as? String,
           !enumValues.contains(value) {
            return false
        }
        // providerConfig object must not contain secrets
        if let config = profile["providerConfig"] as? [String: Any] {
            let configSchema = properties["providerConfig"] as? [String: Any]
            let configProps = configSchema?["properties"] as? [String: Any] ?? [:]
            for key in config.keys where configProps[key] == nil {
                return false
            }
            let redacted = ["username", "password", "accessKey", "secretKey", "token", "sessionToken"]
            for key in config.keys where redacted.contains(key.lowercased()) {
                return false
            }
        }
        return true
    }

    private static func profile(
        schemaVersion: Int,
        originDeviceName: String? = nil,
        providerConfig: [String: Any]? = nil,
        extraTopLevel: [String: Any]? = nil
    ) -> [String: Any] {
        let defaultConfig: [String: Any] = [
            "endpoint": "https://example.com/dav",
            "prefix": NSNull(),
            "region": NSNull(),
            "bucket": NSNull(),
            "pathStyle": NSNull(),
            "certificateFingerprint": NSNull(),
        ]
        var result: [String: Any] = [
            "schemaVersion": schemaVersion,
            "vaultId": "6b1f2a3e-4d5c-4b8a-9f2e-1a2b3c4d5e6f",
            "vaultLocator": "a1b2c3d4e5f60718293a4b5c6d7e8f90",
            "providerType": "webdav",
            "providerConfig": providerConfig ?? defaultConfig,
            "encryptionSuiteVersion": 1,
        ]
        if let originDeviceName {
            result["originDeviceName"] = originDeviceName
        }
        if let extraTopLevel {
            for (k, v) in extraTopLevel { result[k] = v }
        }
        return result
    }

    // MARK: - Tests (must FAIL before T003 bumps the schema to v2)

    @Test
    func schemaArtifactAcceptsV1AndV2() throws {
        // Pre-bump this FAILS (const: 1); after T003 the schema accepts 1 and 2.
        let schema = try Self.schema
        let props = schema["properties"] as? [String: Any] ?? [:]
        let version = props["schemaVersion"] as? [String: Any] ?? [:]
        let accepted = (version["enum"] as? [Int]) ?? []
        #expect(accepted.contains(1), "v1 MUST remain valid (read-compat, Constitution IV)")
        #expect(accepted.contains(2), "schema must be bumped to accept v2 (T003)")
        #expect(!accepted.contains(0) && !accepted.contains(3),
                "unsupported versions MUST NOT validate (fail closed)")
    }

    @Test
    func v1FileParsesUnderV2Validator() throws {
        let schema = try Self.schema
        // A v1 profile: schemaVersion 1, no originDeviceName.
        let v1 = Self.profile(schemaVersion: 1)
        #expect(Self.validate(v1, against: schema),
                "v1 files MUST validate under the v2 validator (backward compatible, Constitution IV)")
    }

    @Test
    func v2FileWithOriginDeviceNameRoundTrips() throws {
        let schema = try Self.schema
        let v2 = Self.profile(schemaVersion: 2, originDeviceName: "Tim's MacBook Pro")
        #expect(Self.validate(v2, against: schema), "v2 file with originDeviceName must validate")
        // The field survives JSON round-trip.
        let data = try JSONSerialization.data(withJSONObject: v2)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["originDeviceName"] as? String == "Tim's MacBook Pro")
    }

    @Test
    func unsupportedSchemaVersionFailsValidation() throws {
        let schema = try Self.schema
        for bad in [0, 3] {
            let file = Self.profile(schemaVersion: bad)
            #expect(!Self.validate(file, against: schema),
                    "schemaVersion \(bad) MUST fail validation (fail closed, FR-010)")
        }
    }

    @Test
    func unknownTopLevelFieldFailsValidation() throws {
        let schema = try Self.schema
        // additionalProperties:false must reject unknown fields (strictness
        // preserved across the v1→v2 bump).
        let file = Self.profile(schemaVersion: 2, extraTopLevel: ["surprise": "nope"])
        #expect(!Self.validate(file, against: schema),
                "unknown top-level fields MUST fail validation (additionalProperties:false)")
    }

    @Test
    func missingRequiredFieldFailsValidation() throws {
        let schema = try Self.schema
        var file = Self.profile(schemaVersion: 2)
        file["vaultLocator"] = nil
        #expect(!Self.validate(file, against: schema), "missing required field MUST fail validation")
    }

    @Test
    func providerConfigNeverCarriesSecrets() throws {
        let schema = try Self.schema
        let leaky = Self.profile(schemaVersion: 2, providerConfig: [
            "endpoint": "https://example.com/dav",
            "username": "alice",
            "password": "hunter2",
            "accessKey": "AKIA...",
            "secretKey": "s3cr3t",
            "sessionToken": "token",
        ])
        #expect(!Self.validate(leaky, against: schema),
                "providerConfig with credentials MUST fail (FR-009/SC-004/CHK029)")
    }
}
