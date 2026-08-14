import Testing
import Foundation
import SyncCore

// MARK: - R2.5 sanitized-code reverse mapping (Phase 2)
//
// The App status surface receives sanitized codes (never raw errors) and
// must reconstruct the category — the mapping previously lived as a
// hardcoded table in the App layer (drift risk, audit A-8). This pins the
// Core single-source API: every sanitized code round-trips.

@Suite struct ProviderErrorCodeMappingTests {

    @Test
    func everySanitizedCodeRoundTrips() {
        let all: [ProviderError] = [
            .auth, .forbidden, .conditionalFailed, .notFound, .conflict,
            .network, .server, .clockSkew, .corrupt, .schemaUnsupported,
            .canceled, .tls, .wrongVault,
        ]
        for error in all {
            let code = error.sanitizedCode
            #expect(ProviderError.fromSanitizedCode(code) == error,
                    "code '\(code)' must round-trip to the same category")
        }
    }

    @Test
    func unknownCodeReturnsNil() {
        #expect(ProviderError.fromSanitizedCode("sync.provider.nonexistent") == nil)
        #expect(ProviderError.fromSanitizedCode("") == nil)
    }

    @Test
    func unmappedDiagnosticCodesReturnNil() {
        // .unmapped carries a diagnostic payload — its code embeds the
        // diagnostic and is NOT reversible to a category (the App treats it
        // as unknown).
        #expect(ProviderError.fromSanitizedCode("sync.provider.unmapped.get.status500") == nil)
    }
}
