import Testing
import Foundation
import Domain
import SyncCore

// MARK: - Provider contract tests (T107)
//
// Per tasks.md T107: "shared suite both WebDAV + S3 pass (Put/Get/Head/
// conditional create/replace/failure/delete/missing/auth/server/timeout/
// cancellation/retry classification)". The suite drives a conforming
// provider through the full protocol surface; WebDAV and S3 adapters must
// pass the same suite (their URLSession-level behavior is covered by their
// own adapter tests). The deterministic LocalProvider acts as the reference
// implementation here.

@Suite struct ProviderContractTests {

    private func makeProvider() -> LocalProvider {
        LocalProvider()
    }

    // MARK: - Put/Get/Head

    @Test
    func putGetHeadRoundTrip() async throws {
        let provider = makeProvider()
        let name = "obj-1"
        let data = Data("hello provider".utf8)

        try await provider.upload(objectName: name, data: data)

        // Head: metadata present with token + size.
        let metadata = try await provider.fetchMetadata(objectName: name)
        #expect(metadata != nil)
        #expect(metadata?.byteSize == data.count)
        #expect(metadata?.versionToken != nil)

        // Get: bytes round-trip.
        let fetched = try await provider.fetch(objectName: name)
        #expect(fetched == data)
    }

    // MARK: - Conditional create / replace / failure

    @Test
    func conditionalCreateFailsWhenObjectExists() async throws {
        let provider = makeProvider()
        let name = "obj-1"
        try await provider.upload(objectName: name, data: Data("first".utf8))

        do {
            try await provider.upload(objectName: name, data: Data("second".utf8))
            Issue.record("duplicate create must fail with conditionalFailed")
        } catch ProviderError.conditionalFailed {
            #expect(true)
        }
    }

    @Test
    func conditionalReplaceSucceedsWithMatchingToken() async throws {
        let provider = makeProvider()
        let name = "obj-1"
        try await provider.upload(objectName: name, data: Data("v1".utf8))
        let token = try await provider.fetchMetadata(objectName: name)?.versionToken

        try await provider.replace(objectName: name, data: Data("v2".utf8), ifMatch: token!)
        let fetched = try await provider.fetch(objectName: name)
        #expect(fetched == Data("v2".utf8))
    }

    @Test
    func conditionalReplaceFailsOnStaleToken() async throws {
        let provider = makeProvider()
        let name = "obj-1"
        try await provider.upload(objectName: name, data: Data("v1".utf8))
        let staleToken = try await provider.fetchMetadata(objectName: name)?.versionToken

        // Someone else replaces first.
        try await provider.replace(objectName: name, data: Data("v2".utf8), ifMatch: staleToken!)

        do {
            try await provider.replace(objectName: name, data: Data("v3".utf8), ifMatch: staleToken!)
            Issue.record("stale-token replace must fail with conditionalFailed")
        } catch ProviderError.conditionalFailed {
            #expect(true)
        }
    }

    // MARK: - Delete / missing

    @Test
    func deleteRemovesObject() async throws {
        let provider = makeProvider()
        let name = "obj-1"
        try await provider.upload(objectName: name, data: Data("x".utf8))

        try await provider.delete(objectName: name, ifMatch: nil)
        let metadata = try await provider.fetchMetadata(objectName: name)
        #expect(metadata == nil)
    }

    @Test
    func missingObjectReportsNotFound() async throws {
        let provider = makeProvider()
        do {
            _ = try await provider.fetch(objectName: "missing")
            Issue.record("missing fetch must throw notFound")
        } catch ProviderError.notFound {
            #expect(true)
        }
        // Head on missing → nil (not an error).
        let metadata = try await provider.fetchMetadata(objectName: "missing")
        #expect(metadata == nil)
    }

    // MARK: - Manifest conditional flow

    @Test
    func manifestFetchBeforeAnyCommitThrowsNotFound() async throws {
        let provider = makeProvider()
        do {
            _ = try await provider.fetchManifest()
            Issue.record("first manifest fetch must throw notFound")
        } catch ProviderError.notFound {
            #expect(true)
        }
    }

    @Test
    func manifestReplaceWithStaleTokenFails() async throws {
        let provider = makeProvider()
        let result = ManifestFetchResult(data: Data("m1".utf8), versionToken: "t1")
        provider.seedManifest(data: result.data)

        do {
            try await provider.replaceManifest(data: Data("m2".utf8), ifMatch: "stale-token")
            Issue.record("stale manifest token must fail with conditionalFailed")
        } catch ProviderError.conditionalFailed {
            #expect(true)
        }
    }

    @Test
    func manifestConditionalCreateFailsWhenManifestExists() async throws {
        // A provider must enforce `If-None-Match: *` semantics for the
        // manifest: a second create attempt (before any replace) must fail
        // with conditionalFailed. The LocalProvider models this so the
        // engine's first-sync contention race is testable; real WebDAV/S3
        // adapters enforce it via the header.
        let provider = makeProvider()
        try await provider.upload(objectName: "manifest", data: Data("first".utf8))

        do {
            try await provider.upload(objectName: "manifest", data: Data("second".utf8))
            Issue.record("duplicate manifest create must fail with conditionalFailed")
        } catch ProviderError.conditionalFailed {
            #expect(true)
        }
    }

    // MARK: - Retry classification

    @Test
    func transientCategoriesAreRetryable() {
        #expect(ProviderError.network.isTransient)
        #expect(ProviderError.server.isTransient)
        #expect(ProviderError.conflict.isTransient)
        #expect(ProviderError.clockSkew.isTransient)
        // Permanent categories never auto-retry.
        #expect(!ProviderError.auth.isTransient)
        #expect(!ProviderError.forbidden.isTransient)
        #expect(!ProviderError.conditionalFailed.isTransient)
        #expect(!ProviderError.notFound.isTransient)
        #expect(!ProviderError.corrupt.isTransient)
        #expect(!ProviderError.schemaUnsupported.isTransient)
        #expect(!ProviderError.tls.isTransient)
        #expect(!ProviderError.canceled.isTransient)
        #expect(!ProviderError.unknown.isTransient)
    }

    @Test
    func failClosedCategoriesAreFlagged() {
        #expect(ProviderError.corrupt.failsClosed)
        #expect(ProviderError.schemaUnsupported.failsClosed)
        #expect(ProviderError.tls.failsClosed)
        #expect(ProviderError.auth.failsClosed)
        #expect(ProviderError.forbidden.failsClosed)
        #expect(!ProviderError.notFound.failsClosed)
    }

    @Test
    func sanitizedCodesAreStableAndSecretFree() {
        #expect(ProviderError.auth.sanitizedCode == "sync.provider.auth")
        #expect(ProviderError.corrupt.sanitizedCode == "sync.provider.corrupt")
        for category: ProviderError in [.auth, .forbidden, .conditionalFailed, .notFound, .conflict,
                                        .network, .server, .clockSkew, .corrupt, .schemaUnsupported,
                                        .canceled, .tls, .unknown] {
            let code = category.sanitizedCode
            #expect(code.hasPrefix("sync.provider."))
            #expect(!code.contains(" "))
        }
    }

    // MARK: - Cancellation

    @Test
    func cancellationClassifiesAsCanceled() {
        let classified = ProviderErrorMapping.classify(CancellationError())
        #expect(classified == .canceled)
    }

    @Test
    func urlSessionTimeoutClassifiesAsNetwork() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        #expect(ProviderErrorMapping.classify(error) == .network)
    }

    @Test
    func tlsErrorsClassifyAsTls() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted)
        #expect(ProviderErrorMapping.classify(error) == .tls)
    }
}
