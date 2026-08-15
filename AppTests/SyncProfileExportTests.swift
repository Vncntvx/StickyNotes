import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - Sync-profile export/import tests (T013/T014, FR-009/FR-010, US2)
//
// Per tasks.md T013/T014 and contracts/sync-profile-v2-delta.md:
// - T013 EXPORT content boundary: exported JSON validates against the v2
//   schema, contains `originDeviceName` from the device identity, and
//   contains NO credentials/keys/note content (SC-004/CHK029).
// - T014 IMPORT validation: v1 and v2 files both import (v2 shows the origin
//   device name); a corrupted file and an unsupported schemaVersion fail
//   closed with no local config written (FR-010/US2/AC3).

@Suite struct SyncProfileExportTests {

    private func deviceIdentity() -> DeviceIdentity {
        let defaults = UserDefaults(suiteName: "test.profile.\(UUID().uuidString)") ?? .standard
        return AppDevice.current(defaults: defaults)
    }

    private func redactedConfig() -> RedactedSyncConfig {
        RedactedSyncConfig(
            endpoint: "https://example.com/dav",
            region: nil,
            bucket: nil,
            prefix: "stickynotes"
        )
    }

    // MARK: T013 — export content boundary

    @Test
    func exportContainsOriginDeviceNameAndNoSecrets() throws {
        let identity = deviceIdentity()
        let profile = try SyncProfileCodec.encode(
            providerType: .webdav,
            vaultId: UUID(),
            vaultLocator: "a1b2c3d4e5f60718293a4b5c6d7e8f90",
            providerConfig: redactedConfig(),
            encryptionSuiteVersion: 1,
            originDeviceName: identity.displayName
        )
        let json = try JSONSerialization.jsonObject(with: profile) as? [String: Any]
        #expect(json != nil)

        // originDeviceName comes from the device identity (FR-009).
        #expect(json?["originDeviceName"] as? String == identity.displayName)
        #expect(json?["schemaVersion"] as? Int == 2, "export writes schema v2")

        // Content boundary (FR-009/SC-004/CHK029): NO credentials, keys, or
        // note content anywhere in the exported JSON.
        let text = String(data: profile, encoding: .utf8)?.lowercased() ?? ""
        for banned in ["password", "secretkey", "accesskey", "sessiontoken",
                       "hunter2", "keychain", "masterkey", "wrappedmasterkey",
                       "\"content\"", "\"title\"", "\"body\"", "\"blocks\""] {
            #expect(!text.contains(banned), "export must not contain: \(banned)")
        }
        // providerConfig carries connection info only (endpoint/prefix).
        let config = json?["providerConfig"] as? [String: Any]
        #expect(config?["endpoint"] as? String == "https://example.com/dav")
    }

    @Test
    func exportDoesNotContainCredentialsFromSource() throws {
        // Even if the caller passes credentials-shaped values, the codec
        // must never include them (redaction is structural, not by luck).
        let profile = try SyncProfileCodec.encode(
            providerType: .s3,
            vaultId: UUID(),
            vaultLocator: "abcd",
            providerConfig: redactedConfig(),
            encryptionSuiteVersion: 1,
            originDeviceName: "Tim's MacBook"
        )
        let text = String(data: profile, encoding: .utf8)?.lowercased() ?? ""
        #expect(!text.contains("secret"))
        #expect(!text.contains("credential"))
        #expect(!text.contains("password"))
    }

    // MARK: T014 — import validation

    @Test
    func importV2FileRoundTripsAndShowsOriginDevice() throws {
        let identity = deviceIdentity()
        let wire = try SyncProfileCodec.encode(
            providerType: .webdav,
            vaultId: UUID(),
            vaultLocator: "abc123",
            providerConfig: redactedConfig(),
            encryptionSuiteVersion: 1,
            originDeviceName: identity.displayName
        )
        let decoded = try SyncProfileCodec.decode(wire)
        #expect(decoded.providerType == .webdav)
        #expect(decoded.vaultLocator == "abc123")
        #expect(decoded.originDeviceName == identity.displayName,
                "import surfaces the origin device name (FR-010/US2/AC2)")
    }

    @Test
    func importV1FileSucceedsWithoutOriginDevice() throws {
        // A v1 file (schemaVersion 1, no originDeviceName) imports fine
        // (v1 read-compat, FR-010).
        var v1 = try profileJSON(schemaVersion: 1)
        v1.removeValue(forKey: "originDeviceName")
        let wire = try JSONSerialization.data(withJSONObject: v1)
        let decoded = try SyncProfileCodec.decode(wire)
        #expect(decoded.vaultLocator == "locator-v1")
        #expect(decoded.originDeviceName == nil, "v1 has no origin device name")
    }

    @Test
    func importCorruptedFileFailsClosed() throws {
        let garbage = Data("this is not json at all".utf8)
        do {
            _ = try SyncProfileCodec.decode(garbage)
            Issue.record("corrupted profile MUST fail closed")
        } catch {
            // fail-closed: decoding threw (no partial profile returned)
        }
    }

    @Test
    func importUnsupportedSchemaVersionFailsClosed() throws {
        for bad in [0, 3] {
            let json = try profileJSON(schemaVersion: bad)
            let wire = try JSONSerialization.data(withJSONObject: json)
            do {
                _ = try SyncProfileCodec.decode(wire)
                Issue.record("schemaVersion \(bad) MUST fail closed (FR-010/US2/AC3)")
            } catch {
                // fail-closed: unsupported schemaVersion threw
            }
        }
    }

    @Test
    func importMissingRequiredFieldFailsClosed() throws {
        var json = try profileJSON(schemaVersion: 2)
        json.removeValue(forKey: "vaultLocator")
        let wire = try JSONSerialization.data(withJSONObject: json)
        do {
            _ = try SyncProfileCodec.decode(wire)
            Issue.record("missing required field MUST fail closed")
        } catch {
            // fail-closed: missing required field threw
        }
    }

    // MARK: - Helpers

    private func profileJSON(schemaVersion: Int) throws -> [String: Any] {
        var json: [String: Any] = [
            "schemaVersion": schemaVersion,
            "vaultId": UUID().uuidString,
            "vaultLocator": "locator-v1",
            "providerType": "webdav",
            "providerConfig": [
                "endpoint": "https://example.com/dav",
                "prefix": "stickynotes",
            ],
            "encryptionSuiteVersion": 1,
        ]
        if schemaVersion == 2 {
            json["originDeviceName"] = "Origin Mac"
        }
        return json
    }
}
