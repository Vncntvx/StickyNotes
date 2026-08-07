import Testing
import Foundation
import Domain
import SyncCore

// MARK: - Diagnostic bundle field-boundary tests (T180, FR-191 clarified 2026-08-07)
//
// Per tasks.md T180: generate a diagnostic bundle from a fixture vault with
// known note/asset content; assert the bundle contains EXACTLY the fields
// enumerated in contracts/diagnostic-bundle.schema.json and NOTHING else;
// assert no note content, titles, summaries, captions, file names/paths,
// window titles, credentials, passwords, key material, raw server responses,
// or remote object names appear anywhere in the bundle.

@Suite struct DiagnosticBundleBoundaryTests {

    // MARK: - Positive field enumeration (exactly the schema fields)

    @Test
    func bundleContainsExactlyTheSchemaFields() throws {
        let bundle = DiagnosticBundleGenerator.generate(
            appVersion: "1.0.0",
            osVersion: "15.0",
            schemaVersionLocal: 1,
            providerType: .webdav,
            recentErrorEvents: [
                DiagnosticErrorEvent(timestamp: Date(), normalizedErrorCategory: "network")
            ],
            syncRunCounts: DiagnosticSyncRunCounts(last24h: 3, last7d: 10, last30d: 30, averageDurationMs: 1500),
            objectCounts: DiagnosticObjectCounts(notes: 5, blocks: 20, assets: 2),
            vaultState: .unlocked,
            permissionStatuses: DiagnosticPermissionStatuses(screenRecording: true, accessibility: false)
        )
        let json = try DiagnosticBundleGenerator.encode(bundle)
        let jsonDict = try JSONSerialization.jsonObject(with: json) as! [String: Any]

        // Required fields per the schema.
        let expectedKeys: Set<String> = [
            "schemaVersion", "appVersion", "osVersion", "schemaVersionLocal",
            "providerType", "recentErrorEvents", "syncRunCounts",
            "objectCounts", "vaultState", "permissionStatuses", "generatedAt"
        ]
        #expect(Set(jsonDict.keys) == expectedKeys, "bundle must contain exactly the schema fields; got: \(jsonDict.keys)")
    }

    // MARK: - No note content / titles / paths / credentials leak

    @Test
    func bundleContainsNoNoteContentOrTitlesOrPaths() throws {
        // Even though the input "knows" about notes with sensitive content,
        // the bundle only carries aggregate counts — never titles, content,
        // captions, or file names/paths.
        let bundle = DiagnosticBundleGenerator.generate(
            appVersion: "1.0.0",
            osVersion: "15.0",
            schemaVersionLocal: 1,
            providerType: .s3,
            recentErrorEvents: [],
            syncRunCounts: nil,
            objectCounts: DiagnosticObjectCounts(notes: 42, blocks: 100, assets: 7),
            vaultState: .locked,
            permissionStatuses: DiagnosticPermissionStatuses(screenRecording: false, accessibility: false)
        )
        let json = try DiagnosticBundleGenerator.encode(bundle)
        let jsonString = String(data: json, encoding: .utf8) ?? ""

        // The bundle must NOT contain sensitive content.
        #expect(!jsonString.contains("my secret note"))
        #expect(!jsonString.contains("/Users/me/Documents"))
        #expect(!jsonString.contains("password"))
        #expect(!jsonString.contains("apiKey"))
        #expect(!jsonString.contains("secret-key"))
        #expect(!jsonString.contains("master-key"))
        #expect(!jsonString.contains("screenshot-caption"))
        #expect(!jsonString.contains("todo-text"))
        #expect(!jsonString.contains("code-block-text"))
        // The aggregate counts ARE present (non-sensitive).
        #expect(jsonString.contains("\"notes\":42"))
        #expect(jsonString.contains("\"blocks\":100"))
        #expect(jsonString.contains("\"assets\":7"))
    }

    @Test
    func bundleProviderTypeNeverExposesEndpointOrCredentials() throws {
        // providerType is "webdav" or "s3" (or nil) — NEVER the endpoint
        // URL, hostname, bucket name, or credentials.
        let bundle = DiagnosticBundleGenerator.generate(
            appVersion: "1.0.0",
            osVersion: "15.0",
            schemaVersionLocal: 1,
            providerType: .webdav,
            recentErrorEvents: [],
            syncRunCounts: nil,
            objectCounts: DiagnosticObjectCounts(),
            vaultState: .unconfigured,
            permissionStatuses: DiagnosticPermissionStatuses(screenRecording: false, accessibility: false)
        )
        let json = try DiagnosticBundleGenerator.encode(bundle)
        let jsonString = String(data: json, encoding: .utf8) ?? ""
        #expect(jsonString.contains("\"providerType\":\"webdav\""))
        #expect(!jsonString.contains("https://dav.example.com"))
        #expect(!jsonString.contains("my-bucket"))
        #expect(!jsonString.contains("AKIAIOSFODNN7EXAMPLE"))
    }

    // MARK: - Error events carry only timestamp + category

    @Test
    func errorEventsCarryOnlyTimestampAndCategory() throws {
        let bundle = DiagnosticBundleGenerator.generate(
            appVersion: "1.0.0",
            osVersion: "15.0",
            schemaVersionLocal: 1,
            providerType: nil,
            recentErrorEvents: [
                DiagnosticErrorEvent(timestamp: Date(timeIntervalSince1970: 1_700_000_000), normalizedErrorCategory: "auth"),
                DiagnosticErrorEvent(timestamp: Date(timeIntervalSince1970: 1_700_000_100), normalizedErrorCategory: "wrongVault"),
            ],
            syncRunCounts: nil,
            objectCounts: DiagnosticObjectCounts(),
            vaultState: .unconfigured,
            permissionStatuses: DiagnosticPermissionStatuses(screenRecording: false, accessibility: false)
        )
        let json = try DiagnosticBundleGenerator.encode(bundle)
        let dict = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let events = dict["recentErrorEvents"] as! [[String: Any]]
        #expect(events.count == 2)
        for event in events {
            #expect(Set(event.keys) == Set(["timestamp", "normalizedErrorCategory"]))
        }
        // No raw server response/body in the event.
        let jsonString = String(data: json, encoding: .utf8) ?? ""
        #expect(!jsonString.contains("HTTP 401"))
        #expect(!jsonString.contains("Unauthorized"))
    }

    @Test
    func unknownErrorCategoriesMappedToUnknown() {
        let bundle = DiagnosticBundleGenerator.generate(
            appVersion: "1.0.0",
            osVersion: "15.0",
            schemaVersionLocal: 1,
            providerType: nil,
            recentErrorEvents: [
                DiagnosticErrorEvent(timestamp: Date(), normalizedErrorCategory: "not-a-real-category"),
            ],
            syncRunCounts: nil,
            objectCounts: DiagnosticObjectCounts(),
            vaultState: .unconfigured,
            permissionStatuses: DiagnosticPermissionStatuses(screenRecording: false, accessibility: false)
        )
        #expect(bundle.recentErrorEvents[0].normalizedErrorCategory == "unknown")
    }

    // MARK: - Unconfigured sync → vaultState = unconfigured, providerType = nil

    @Test
    func unconfiguredSyncShowsUnconfiguredVaultStateAndNilProviderType() throws {
        let bundle = DiagnosticBundleGenerator.generate(
            appVersion: "1.0.0",
            osVersion: "15.0",
            schemaVersionLocal: 1,
            providerType: nil,
            recentErrorEvents: [],
            syncRunCounts: nil,
            objectCounts: DiagnosticObjectCounts(),
            vaultState: .unconfigured,
            permissionStatuses: DiagnosticPermissionStatuses(screenRecording: false, accessibility: false)
        )
        #expect(bundle.providerType == nil, "unconfigured sync → providerType is nil")
        #expect(bundle.vaultState == .unconfigured)
        let json = try DiagnosticBundleGenerator.encode(bundle)
        let jsonString = String(data: json, encoding: .utf8) ?? ""
        #expect(jsonString.contains("\"vaultState\":\"unconfigured\""))
        // The providerType key encodes as null (JSONEncoder encodes nil
        // optionals as null when the key is present in the Codable struct).
        #expect(jsonString.contains("\"providerType\":null") || !jsonString.contains("providerType"))
    }

    // MARK: - Schema version is 1

    @Test
    func bundleSchemaVersionIsOne() {
        let bundle = DiagnosticBundleGenerator.generate(
            appVersion: "1.0.0",
            osVersion: "15.0",
            schemaVersionLocal: 1,
            providerType: nil,
            recentErrorEvents: [],
            syncRunCounts: nil,
            objectCounts: DiagnosticObjectCounts(),
            vaultState: .unconfigured,
            permissionStatuses: DiagnosticPermissionStatuses(screenRecording: false, accessibility: false)
        )
        #expect(bundle.schemaVersion == 1)
    }
}
