import Foundation
import AppKit
import Domain

// MARK: - FileDragOutBridge (T166)
//
// Per tasks.md T166 and plan §File-reference architecture:
// - Drag-out COPIES the file (never moves or deletes the original).
// - An explicit move requires a destination picker + confirmation +
//   verify-before-replace (the moved file must match the bookmarked file
//   before the bookmark is re-pointed).
// - No filesystem-wide scan (constitution VI/IX).
//
// The verify-before-replace decision is a pure function (testable headlessly
// — T163e/T059 FileReferenceAccessTests); file I/O happens in the running
// app only.

/// The drag-out + explicit-move bridge.
public enum FileDragOutBridge {

    /// File identities used for move verification.
    public struct FileIdentity: Sendable, Equatable {
        public let size: Int
        public let modificationDate: Date

        public init(size: Int, modificationDate: Date) {
            self.size = size
            self.modificationDate = modificationDate
        }
    }

    /// Reads the identity of a file (for verify-before-replace). Returns nil
    /// when the file is unreadable or missing.
    public static func identity(of url: URL) -> FileIdentity? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values?.fileSize else { return nil }
        return FileIdentity(size: size, modificationDate: values?.contentModificationDate ?? Date.distantPast)
    }

    /// The verify-before-replace decision for an explicit move (FR-102):
    /// the destination is only replaced when the existing destination file
    /// is either absent or IDENTICAL to the source (a previous interrupted
    /// move). Replacing a different file is refused — the caller must ask
    /// the user to confirm.
    public enum ReplaceDecision: Sendable, Equatable {
        case safeToProceed          // destination absent or identical
        case wouldOverwriteDifferentFile
    }

    public static func decideReplace(
        source: FileIdentity,
        destination: FileIdentity?
    ) -> ReplaceDecision {
        guard let destination else { return .safeToProceed }
        if destination == source { return .safeToProceed }
        return .wouldOverwriteDifferentFile
    }

    /// After a successful explicit move, verifies the moved file at the new
    /// location matches the source identity (verify-before-replace-bookmark).
    public static func verifyMoveCompleted(source: FileIdentity, movedFile: FileIdentity?) -> Bool {
        movedFile == source
    }
}
