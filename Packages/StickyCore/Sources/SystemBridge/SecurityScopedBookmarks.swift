import Foundation
import AppKit
import Domain

// MARK: - SecurityScopedBookmarks (T166)
//
// Per tasks.md T166 and plan §File-reference architecture: security-scoped
// bookmark access (balanced start/stop), availability status, relink.
// Device-local only — bookmark bytes and absolute paths NEVER enter
// canonical JSON or sync (FR-105; constitution IX).
//
// The availability classification is a pure function of the resolution
// outcome (testable headlessly — T163e/T059 FileReferenceAccessTests). The
// actual bookmark creation/resolution requires user-selected-file security
// scope (sandbox), which only works in the running app.

/// Outcomes of attempting to resolve a bookmark to a file.
public enum BookmarkResolution: Sendable, Equatable {
    /// Bookmark resolved and the file exists.
    case resolved(URL)
    /// Bookmark resolved but the file no longer exists (moved/deleted).
    case fileMissing(URL)
    /// The bookmark data itself could not be resolved (stale bookmark).
    case staleBookmark
    /// No bookmark exists for this block (e.g. synchronized metadata with
    /// no local file — FR-104 on-another-device).
    case noBookmark
    /// Starting security-scoped access failed.
    case accessDenied
}

/// Availability classification per FR-100: available / missing / stale /
/// on-another-device (plus the transient relinked state).
public enum FileAvailabilityClassifier {
    /// Maps a bookmark-resolution outcome to the four-state FR-100 model
    /// (each state is communicated by more than color alone in the App UI —
    /// icon + text; FR-044).
    public static func availability(from resolution: BookmarkResolution) -> FileAvailability {
        switch resolution {
        case .resolved:
            return .available
        case .fileMissing:
            return .missing
        case .staleBookmark:
            return .stale
        case .noBookmark:
            return .onAnotherDevice
        case .accessDenied:
            return .stale
        }
    }
}

/// The security-scoped bookmark bridge. All methods must run on the main
/// actor (AppKit/security-scope access).
public enum SecurityScopedBookmarks {

    /// Creates a security-scoped bookmark for a user-selected file.
    public static func createBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw StickyError.fileRefAccess(.bookmarkMissing)
        }
    }

    /// Resolves a bookmark and classifies availability. Never throws on a
    /// stale/missing outcome — it returns the classification (the caller
    /// offers relink per FR-103).
    @MainActor
    public static func resolve(bookmarkData: Data) -> BookmarkResolution {
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            return .staleBookmark
        }

        // Balanced start/stop of security-scoped access (FR-102): every
        // resolve that starts access must stop it before returning.
        guard url.startAccessingSecurityScopedResource() else {
            return .accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        if isStale {
            // Bookmark unresolved (stale) but the file may still exist —
            // per FR-100 the state is "stale", not "missing".
            return .staleBookmark
        }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else {
            return .fileMissing(url)
        }
        return .resolved(url)
    }

    /// Creates a fresh bookmark from a relinked URL (FR-103 relink).
    public static func relink(bookmarkData: Data, to url: URL) throws -> Data {
        // Balanced access on the old bookmark while verifying the new one.
        var oldStale = false
        guard let oldURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &oldStale
        ) else {
            // Old bookmark unusable — the new one alone is enough (relink).
            return try createBookmark(for: url)
        }
        let accessed = oldURL.startAccessingSecurityScopedResource()
        defer { if accessed { oldURL.stopAccessingSecurityScopedResource() } }
        return try createBookmark(for: url)
    }
}
