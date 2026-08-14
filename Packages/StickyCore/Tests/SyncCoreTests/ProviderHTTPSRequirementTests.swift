import Testing
import Foundation
import Domain
import SyncCore

// MARK: - HTTPS-only requirement (remediation-phase1 R1.5, T019)
//
// Constitution VIII declares HTTPS-only transport for sync repositories;
// the adapters previously accepted any scheme (verified 2026-08-14 — no
// scheme check existed in either provider). This suite pins the fail-fast
// contract: an http:// endpoint must be rejected AT CONSTRUCTION with
// StickyError.credentials(.invalidEndpoint); https:// must pass.

@Suite struct ProviderHTTPSRequirementTests {

    private func makeWebDAVConfig(scheme: String) -> WebDAVConfiguration {
        WebDAVConfiguration(
            baseURL: URL(string: "\(scheme)://example.com/dav")!,
            containerPath: "vault"
        )
    }

    private func makeS3Config(scheme: String) -> S3Configuration {
        S3Configuration(
            endpoint: URL(string: "\(scheme)://s3.example.com")!,
            region: "us-east-1",
            bucket: "bucket",
            prefix: "vault",
            accessKey: "AKIDEXAMPLE",
            secretKey: "secret"
        )
    }

    // MARK: - WebDAV

    @Test
    func webdavRejectsHTTPEndpointAtConstruction() {
        do {
            _ = try WebDAVProvider(config: makeWebDAVConfig(scheme: "http"))
            Issue.record("expected .invalidEndpoint for http:// endpoint")
        } catch StickyError.credentials(.invalidEndpoint) {
            // Expected: HTTPS-only (constitution VIII), fail fast.
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test
    func webdavAcceptsHTTPSEndpoint() throws {
        // Must not reject legitimate HTTPS endpoints (no false positive).
        _ = try WebDAVProvider(config: makeWebDAVConfig(scheme: "https"))
    }

    // MARK: - S3

    @Test
    func s3RejectsHTTPEndpointAtConstruction() {
        do {
            _ = try S3Provider(config: makeS3Config(scheme: "http"))
            Issue.record("expected .invalidEndpoint for http:// endpoint")
        } catch StickyError.credentials(.invalidEndpoint) {
            // Expected: HTTPS-only (constitution VIII), fail fast.
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test
    func s3AcceptsHTTPSEndpoint() throws {
        _ = try S3Provider(config: makeS3Config(scheme: "https"))
    }
}
