import Foundation
import Domain

// MARK: - ProviderErrors (T116)
//
// Per contracts/provider-errors.md: the normalized error vocabulary both
// WebDAV and S3 adapters map to. The engine branches on these categories,
// never on raw HTTP status/S3 XML. Stable domain `sync.provider`; sanitized
// codes only (no note content, credentials, or full remote responses).

/// Normalized provider error categories (provider-errors.md).
public enum ProviderError: Error, Sendable, Equatable {
    case auth
    case forbidden
    case conditionalFailed
    case notFound
    case conflict
    case network
    case server
    case clockSkew
    case corrupt
    case schemaUnsupported
    case canceled
    case tls
    /// Wrong vault detected (FR edge case, clarified 2026-08-07): the
    /// bootstrap object's `vaultId` does not match the locally-configured
    /// `vaultId`, or a bootstrap already exists under the chosen locator
    /// for a new vault. Fail-closed; no local/remote mutation.
    case wrongVault
    case unknown

    /// Stable sanitized code for logs/diagnostics (`sync.provider.<code>`).
    public var sanitizedCode: String {
        switch self {
        case .auth: return "sync.provider.auth"
        case .forbidden: return "sync.provider.forbidden"
        case .conditionalFailed: return "sync.provider.conditionalFailed"
        case .notFound: return "sync.provider.notFound"
        case .conflict: return "sync.provider.conflict"
        case .network: return "sync.provider.network"
        case .server: return "sync.provider.server"
        case .clockSkew: return "sync.provider.clockSkew"
        case .corrupt: return "sync.provider.corrupt"
        case .schemaUnsupported: return "sync.provider.schemaUnsupported"
        case .canceled: return "sync.provider.canceled"
        case .tls: return "sync.provider.tls"
        case .wrongVault: return "sync.provider.wrongVault"
        case .unknown: return "sync.provider.unknown"
        }
    }

    /// Whether the category is eligible for bounded retry (provider-errors.md:
    /// transient categories only).
    public var isTransient: Bool {
        switch self {
        case .network, .server, .conflict, .clockSkew:
            return true
        case .auth, .forbidden, .conditionalFailed, .notFound, .corrupt,
             .schemaUnsupported, .canceled, .tls, .wrongVault, .unknown:
            return false
        }
    }

    /// Whether the category must FAIL CLOSED (never accept an object, never
    /// overwrite/delete local data).
    public var failsClosed: Bool {
        switch self {
        case .corrupt, .schemaUnsupported, .tls, .auth, .forbidden, .wrongVault:
            return true
        default:
            return false
        }
    }
}

/// Maps URLSession-style transport errors to provider categories.
public enum ProviderErrorMapping {
    /// Classifies an underlying error into a normalized category.
    public static func classify(_ error: Error) -> ProviderError {
        if error is CancellationError {
            return .canceled
        }
        if let provider = error as? ProviderError {
            return provider
        }
        let nsError = error as NSError
        switch nsError.domain {
        case NSURLErrorDomain:
            switch nsError.code {
            case NSURLErrorCancelled:
                return .canceled
            case NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet, NSURLErrorDNSLookupFailed,
                 NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
                return .network
            case NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid,
                 NSURLErrorClientCertificateRejected, NSURLErrorClientCertificateRequired,
                 NSURLErrorSecureConnectionFailed:
                return .tls
            default:
                return .network
            }
        default:
            return .unknown
        }
    }
}
