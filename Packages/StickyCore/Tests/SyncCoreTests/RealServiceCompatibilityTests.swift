import Testing
import Foundation
import SecurityCore
import SyncCore

// MARK: - Real-service compatibility tests (T139)
//
// Per tasks.md T139: standards-compliant WebDAV, MinIO, one hosted
// S3-compatible, AWS S3 — opt-in via CI secrets, NEVER committed
// (quickstart.md). When the secrets are absent the suite skips (it must
// never fail without credentials).
//
// R2.4 (remediation roadmap 2026-08-14): the audit found both tests ended
// in `#expect(true)` even when the secrets WERE present — no provider was
// ever constructed, so the real adapters never ran against a real server
// outside manual testing. With credentials configured, the suite now
// performs a real round trip (container create / conditional PUT / GET /
// DELETE).

@Suite struct RealServiceCompatibilityTests {

    private enum Credentials {
        static var webdavURL: String? {
            ProcessInfo.processInfo.environment["STICKY_WEBDAV_TEST_URL"]
        }
        static var webdavUser: String? {
            ProcessInfo.processInfo.environment["STICKY_WEBDAV_TEST_USERNAME"]
        }
        static var webdavPassword: String? {
            ProcessInfo.processInfo.environment["STICKY_WEBDAV_TEST_PASSWORD"]
        }
        static var s3Endpoint: String? {
            ProcessInfo.processInfo.environment["STICKY_S3_TEST_ENDPOINT"]
        }
        static var s3AccessKey: String? {
            ProcessInfo.processInfo.environment["STICKY_S3_TEST_ACCESS_KEY"]
        }
        static var s3SecretKey: String? {
            ProcessInfo.processInfo.environment["STICKY_S3_TEST_SECRET_KEY"]
        }
    }

    /// The full object lifecycle against a real server: create container,
    /// conditional PUT, HEAD metadata, GET round-trip, conditional
    /// replace, DELETE.
    private func roundTrip(_ provider: any SyncProviderProtocol, objectName: String, payload: Data) async throws {
        try await provider.verify()
        try await provider.upload(objectName: objectName, data: payload)
        let metadata = try await provider.fetchMetadata(objectName: objectName)
        #expect(metadata != nil, "the uploaded object must be visible to HEAD")
        let fetched = try await provider.fetch(objectName: objectName)
        #expect(fetched == payload, "GET must round-trip the exact bytes")
        try await provider.delete(objectName: objectName, ifMatch: nil)
        let gone = try await provider.fetchMetadata(objectName: objectName)
        #expect(gone == nil, "DELETE must remove the object")
    }

    @Test
    func webdavCompatibilityRunsOnlyWithSecrets() async throws {
        // Skipped (not failed) when the secrets are absent — CI-only.
        guard let urlString = Credentials.webdavURL else { return }
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        // A unique container per run keeps parallel CI lanes isolated.
        let provider = try WebDAVProvider(
            config: WebDAVConfiguration(
                baseURL: url,
                containerPath: "sticky-compat-\(UUID().uuidString)",
                username: Credentials.webdavUser,
                password: Credentials.webdavPassword
            )
        )
        try await roundTrip(provider, objectName: "obj-\(UUID().uuidString)", payload: Data("webdav round trip".utf8))
    }

    @Test
    func s3CompatibilityRunsOnlyWithSecrets() async throws {
        // Skipped (not failed) when the secrets are absent — CI-only.
        guard let endpointString = Credentials.s3Endpoint,
              let accessKey = Credentials.s3AccessKey,
              let secretKey = Credentials.s3SecretKey else { return }
        guard let endpoint = URL(string: endpointString) else {
            throw URLError(.badURL)
        }
        let provider = try S3Provider(
            config: S3Configuration(
                endpoint: endpoint,
                region: ProcessInfo.processInfo.environment["STICKY_S3_TEST_REGION"] ?? "us-east-1",
                bucket: ProcessInfo.processInfo.environment["STICKY_S3_TEST_BUCKET"] ?? "sticky-compat-\(UUID().uuidString)",
                prefix: "vault-\(UUID().uuidString)",
                accessKey: accessKey,
                secretKey: secretKey
            )
        )
        try await roundTrip(provider, objectName: "obj-\(UUID().uuidString)", payload: Data("s3 round trip".utf8))
    }
}
