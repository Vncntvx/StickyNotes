import Foundation
import os

// MARK: - OSLog Logger wrappers with privacy annotations (T025)
//
// Per plan §Diagnostics and logging:
//
// - OSLog `Logger` with privacy annotations (dynamic values private by
//   default).
// - Logs NEVER include content/titles/todo/code/file names/paths/window
//   titles/captions/credentials/passwords/key material/complete responses/
//   full object names where avoidable.
// - Stable error domains + sanitized codes.
// - OS signposts on measurable paths.
//
// This file provides the project's Logger wrappers. The subsystem is shared
// across all StickyCore modules; each module gets a category for filtering.

/// The shared OSLog subsystem for the StickyNotes app + StickyCore package.
/// Replace the placeholder bundle id with the final one when chosen.
public enum StickyLogSubsystem {
    public static let subsystem = "local.stickynotes"
}

/// Per-module log categories. Use these to filter in Console.app:
/// `subsystem == local.stickynotes AND category == <category>`.
public enum StickyLogCategory: String, Sendable {
    case domain
    case persistence
    case editor
    case assetStore
    case security
    case sync
    case systemBridge
    case app
    case widget
    case migration
    case performance
}

/// A thin wrapper around `os.Logger` that enforces the project's privacy
/// rules. All dynamic values are private by default — call sites must
/// explicitly opt a value into `.public` if it is non-sensitive (e.g., an
/// operation name) and even then must NOT pass content/paths/secrets.
public struct StickyLogger: Sendable {
    public let logger: Logger
    /// The underlying `OSLog` — needed for `os_signpost` (the modern
    /// `Logger` does not expose it directly).
    public let osLog: OSLog

    public init(category: StickyLogCategory) {
        let osLog = OSLog(
            subsystem: StickyLogSubsystem.subsystem,
            category: category.rawValue
        )
        self.osLog = osLog
        self.logger = Logger(osLog)
    }

    /// Convenience for module-level singletons.
    public static let domain = StickyLogger(category: .domain)
    public static let persistence = StickyLogger(category: .persistence)
    public static let editor = StickyLogger(category: .editor)
    public static let assetStore = StickyLogger(category: .assetStore)
    public static let security = StickyLogger(category: .security)
    public static let sync = StickyLogger(category: .sync)
    public static let systemBridge = StickyLogger(category: .systemBridge)
    public static let migration = StickyLogger(category: .migration)
    public static let performance = StickyLogger(category: .performance)

    // MARK: - Privacy-safe logging helpers
    //
    // The helpers below take only sanitized, non-sensitive identifiers (UUIDs,
    // counts, op names, error codes). They NEVER accept note content, file
    // paths, credentials, or any value covered by FR-191/SC-010.

    /// Logs a debug message. The `op` and `code` arguments are public
    /// (operation names and sanitized codes are not sensitive); any
    /// additional context MUST be passed as an explicit, sanitized string
    /// the call site has already redacted.
    public func debug(_ op: String, code: String? = nil, sanitizedContext: String? = nil) {
        if let code, let sanitizedContext {
            logger.debug("op=\(op, privacy: .public) code=\(code, privacy: .public) ctx=\(sanitizedContext, privacy: .public)")
        } else if let code {
            logger.debug("op=\(op, privacy: .public) code=\(code, privacy: .public)")
        } else {
            logger.debug("op=\(op, privacy: .public)")
        }
    }

    public func info(_ op: String, code: String? = nil) {
        if let code {
            logger.info("op=\(op, privacy: .public) code=\(code, privacy: .public)")
        } else {
            logger.info("op=\(op, privacy: .public)")
        }
    }

    public func warning(_ op: String, code: String) {
        logger.warning("op=\(op, privacy: .public) code=\(code, privacy: .public)")
    }

    public func error(_ op: String, code: String) {
        logger.error("op=\(op, privacy: .public) code=\(code, privacy: .public)")
    }

    /// Logs an error from a `StickyError`, using its `sanitizedCode`. The
    /// underlying error is NOT logged verbatim — only the sanitized code is.
    public func error(_ op: String, stickyError: StickyError) {
        logger.error("op=\(op, privacy: .public) code=\(stickyError.sanitizedCode, privacy: .public)")
    }

    /// Logs a count for capacity/throughput observability. Counts are
    /// non-sensitive.
    public func noticeCount(_ op: String, count: Int) {
        logger.notice("op=\(op, privacy: .public) count=\(count, privacy: .public)")
    }

    // MARK: - Signposts (performance / SC-001..SC-011)
    //
    // Signposts carry NO note content — only op names and (optionally)
    // sanitized identifiers. Uses the modern `OSSignposter` API (macOS 12+).
    // Signpost names MUST be `StaticString` (Instruments requires statically
    // resolvable names).

    private var signposter: OSSignposter {
        OSSignposter(subsystem: StickyLogSubsystem.subsystem, category: "performance")
    }

    /// Emits a signpost interval begin. The returned state MUST be passed to
    /// `signpostEnd(_:op:)` to close the interval. The `op` name MUST be a
    /// static string literal (Instruments requires it).
    @discardableResult
    public func signpostBegin(_ op: StaticString) -> OSSignpostIntervalState {
        let signposter = self.signposter
        let id = signposter.makeSignpostID()
        return signposter.beginInterval(op, id: id)
    }

    public func signpostEnd(_ state: OSSignpostIntervalState, op: StaticString) {
        signposter.endInterval(op, state)
    }
}
