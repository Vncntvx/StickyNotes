import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - SyncLocationPresentation tests (Settings polish round 3, 2026-08-14)
//
// Schema-based matrix (NOT a hex heuristic). The verified persisted schema
// stores only the user folder in `RedactedSyncConfig.prefix`; display rules:
// 1. leading segment == vaultLocator/replacedFromVaultLocator → stripped
//    (legacy auto-generated layout);
// 2. any remaining segment satisfying `RemoteLayout.isOpaque` → schema
//    non-conformance → `location` returns nil (honest degradation; caller
//    shows provider-only copy, technical path stays in Advanced);
// 3. everything else is kept verbatim.

@Suite struct SyncLocationPresentationTests {

    private static let locator = "1f4d49806f5549acabaa39e5f2ea7c13"
    private static let replacedLocator = "b2e3c4d5e6f7a8b9c0d1e2f3a4b5c6d7"
    /// A 32-hex user-defined segment that happens to NOT be any locator.
    private static let userHex = "aa11bb22cc33dd44ee55ff66aa77bb88"

    private func s3Config(
        prefix: String?,
        bucket: String = "my-bucket",
        replacedFrom: String? = nil
    ) -> VaultConfiguration {
        VaultConfiguration(
            vaultId: UUID(),
            vaultLocator: Self.locator,
            providerType: .s3,
            providerConfig: RedactedSyncConfig(
                endpoint: "https://s3.example.com",
                region: "us-east-1",
                bucket: bucket,
                prefix: prefix
            ),
            keychainCredentialRef: "ref",
            replacedFromVaultLocator: replacedFrom
        )
    }

    private func webdavConfig(prefix: String?, endpoint: String = "https://example.com/dav/") -> VaultConfiguration {
        VaultConfiguration(
            vaultId: UUID(),
            vaultLocator: Self.locator,
            providerType: .webdav,
            providerConfig: RedactedSyncConfig(endpoint: endpoint, prefix: prefix),
            keychainCredentialRef: "ref"
        )
    }

    // Current-schema configs: the user folder is kept verbatim.

    @Test
    func currentS3ConfigKeepsUserPrefix() {
        #expect(SyncLocationPresentation.location(for: s3Config(prefix: "StickyNotes")) == "my-bucket/StickyNotes")
        #expect(SyncLocationPresentation.location(for: s3Config(prefix: "Notes/Work")) == "my-bucket/Notes/Work")
    }

    @Test
    func currentWebDAVConfigKeepsUserPrefix() {
        #expect(SyncLocationPresentation.location(for: webdavConfig(prefix: "Notes")) == "example.com/dav/Notes")
    }

    // Legacy layouts: leading locator segment stripped.

    @Test
    func legacyS3LeadingLocatorSegmentIsHidden() {
        let config = s3Config(prefix: "\(Self.locator)/StickyNotes")
        #expect(SyncLocationPresentation.location(for: config) == "my-bucket/StickyNotes")
    }

    @Test
    func legacyWebDAVLeadingLocatorSegmentIsHidden() {
        let config = webdavConfig(prefix: "\(Self.locator)/StickyNotes")
        #expect(SyncLocationPresentation.location(for: config) == "example.com/dav/StickyNotes")
    }

    @Test
    func legacyLocatorOnlyPrefixFallsBackToBase() {
        #expect(SyncLocationPresentation.location(for: s3Config(prefix: Self.locator)) == "my-bucket")
        #expect(SyncLocationPresentation.location(for: webdavConfig(prefix: Self.locator)) == "example.com/dav")
    }

    @Test
    func leadingReplacedLocatorSegmentIsHidden() {
        let config = s3Config(prefix: "\(Self.replacedLocator)/StickyNotes", replacedFrom: Self.replacedLocator)
        #expect(SyncLocationPresentation.location(for: config) == "my-bucket/StickyNotes")
    }

    // Opaque segments that cannot be schema-resolved → honest degradation.

    @Test
    func userDefinedOpaqueSegmentDegradesHonestly() {
        // A 32-hex segment that is not any known locator still satisfies the
        // repo's structural generated-namespace predicate: the prefix no
        // longer conforms to the user-folder schema, so we must NOT guess a
        // path — location is nil and the caller shows provider-only copy.
        #expect(SyncLocationPresentation.location(for: s3Config(prefix: "\(Self.userHex)/Photos")) == nil)
    }

    @Test
    func opaqueSegmentInNonLeadingPositionDegradesHonestly() {
        #expect(SyncLocationPresentation.location(for: s3Config(prefix: "Photos/\(Self.locator)")) == nil)
    }

    // Empty / unset prefix → base only.

    @Test
    func emptyOrNilPrefixShowsBaseOnly() {
        #expect(SyncLocationPresentation.location(for: s3Config(prefix: nil)) == "my-bucket")
        #expect(SyncLocationPresentation.location(for: s3Config(prefix: "")) == "my-bucket")
        #expect(SyncLocationPresentation.location(for: s3Config(prefix: "///")) == "my-bucket")
        #expect(SyncLocationPresentation.location(for: webdavConfig(prefix: nil)) == "example.com/dav")
    }

    @Test
    func webdavEndpointDisplayStripsScheme() {
        #expect(SyncLocationPresentation.endpointHost("https://example.com/dav/") == "example.com/dav")
        #expect(SyncLocationPresentation.endpointHost("https://example.com") == "example.com")
        #expect(SyncLocationPresentation.endpointHost("not-a-url") == "not-a-url")
    }

    @Test
    func s3WithoutBucketFallsBackToEndpoint() {
        let config = s3Config(prefix: nil, bucket: "")
        #expect(SyncLocationPresentation.location(for: config) == "https://s3.example.com")
    }

    @Test
    func technicalPathKeepsFullProtocolValue() {
        let config = s3Config(prefix: "\(Self.locator)/StickyNotes")
        #expect(SyncLocationPresentation.technicalPath(for: config) == "my-bucket/\(Self.locator)/StickyNotes")
    }
}

// MARK: - Vault ID presentation tests (Settings polish round 3, 2026-08-14)

@Suite struct VaultIDPresentationTests {

    @Test
    func normalLocatorIsAbbreviated() {
        #expect(VaultIDPresentation.abbreviated("1870ff55fee5472cb3fa2591b87c5299") == "1870ff55…c5299")
    }

    @Test
    func shortValuePassesThroughUnchanged() {
        #expect(VaultIDPresentation.abbreviated("short") == "short")
        #expect(VaultIDPresentation.abbreviated("1234567890abc") == "1234567890abc")
    }

    @Test
    func emptyValueRendersDash() {
        #expect(VaultIDPresentation.abbreviated("") == "—")
    }

    @Test
    func boundaryLengthThirteenStaysWhole() {
        // count == 13 is not abbreviated (guard id.count > 13).
        #expect(VaultIDPresentation.abbreviated("1234567890abc") == "1234567890abc")
        #expect(VaultIDPresentation.abbreviated("1234567890abcd") == "12345678…0abcd")
    }
}
