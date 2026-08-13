import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - SyncLocationPresentation tests (Settings polish round 2, 2026-08-14)
//
// Pins the legacy-layout recognition contract for the Storage display
// value: ONLY the auto-generated legacy layout (`<locator>` or
// `<locator>/<user-folder>…` as the LEADING segment of the persisted
// prefix) is stripped. Ordinary user prefixes, user-typed 32-hex segments,
// and the locator in any non-leading position are kept verbatim — no
// generic locator filtering.

@Suite struct SyncLocationPresentationTests {

    private static let locator = "1f4d49806f5549acabaa39e5f2ea7c13"
    /// A 32-hex user-defined segment that happens to NOT be the locator.
    private static let userHex = "aa11bb22cc33dd44ee55ff66aa77bb88"

    private func s3Config(prefix: String?, bucket: String = "my-bucket") -> VaultConfiguration {
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
            keychainCredentialRef: "ref"
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

    @Test
    func legacyLeadingLocatorSegmentIsHidden() {
        // Legacy auto-generated layout "<locator>/StickyNotes" → the locator
        // is stripped, the user folder remains.
        let config = s3Config(prefix: "\(Self.locator)/StickyNotes")
        #expect(SyncLocationPresentation.location(for: config) == "my-bucket/StickyNotes")
    }

    @Test
    func legacyLocatorOnlyPrefixFallsBackToBucketOrHost() {
        #expect(SyncLocationPresentation.location(for: s3Config(prefix: Self.locator)) == "my-bucket")
        #expect(SyncLocationPresentation.location(for: webdavConfig(prefix: Self.locator)) == "example.com/dav")
    }

    @Test
    func normalUserPrefixIsKeptVerbatim() {
        #expect(SyncLocationPresentation.location(for: s3Config(prefix: "StickyNotes")) == "my-bucket/StickyNotes")
        #expect(SyncLocationPresentation.location(for: s3Config(prefix: "Notes/Work")) == "my-bucket/Notes/Work")
    }

    @Test
    func userDefinedHexSegmentIsKeptVerbatim() {
        // A 32-hex segment that is NOT the vault locator is user data.
        let config = s3Config(prefix: "\(Self.userHex)/Photos")
        #expect(SyncLocationPresentation.location(for: config) == "my-bucket/\(Self.userHex)/Photos")
    }

    @Test
    func locatorInNonLeadingPositionIsKeptVerbatim() {
        // The locator in a non-legacy position is user data — not stripped.
        let config = s3Config(prefix: "Photos/\(Self.locator)")
        #expect(SyncLocationPresentation.location(for: config) == "my-bucket/Photos/\(Self.locator)")
    }

    @Test
    func emptyOrNilPrefixShowsBucketOrHostOnly() {
        #expect(SyncLocationPresentation.location(for: s3Config(prefix: nil)) == "my-bucket")
        #expect(SyncLocationPresentation.location(for: s3Config(prefix: "")) == "my-bucket")
        #expect(SyncLocationPresentation.location(for: webdavConfig(prefix: nil)) == "example.com/dav")
    }

    @Test
    func webdavEndpointDisplayStripsScheme() {
        #expect(SyncLocationPresentation.endpointHost("https://example.com/dav/") == "example.com/dav")
        #expect(SyncLocationPresentation.endpointHost("https://example.com") == "example.com")
        #expect(SyncLocationPresentation.endpointHost("not-a-url") == "not-a-url")
        #expect(
            SyncLocationPresentation.location(for: webdavConfig(prefix: "Notes")) == "example.com/dav/Notes"
        )
    }

    @Test
    func s3WithoutBucketFallsBackToEndpoint() {
        let config = s3Config(prefix: nil, bucket: "")  // bucket empty → endpoint
        #expect(SyncLocationPresentation.location(for: config) == "https://s3.example.com")
    }
}
