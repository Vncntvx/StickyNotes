import SwiftUI
import AppKit
import Domain

// MARK: - DeepLinkRouter (T169, contracts/deep-links.md)
//
// Per tasks.md T169 and contracts/deep-links.md: URL routing
// `stickynotes://note/<uuid>`, `stickynotes://new`, `stickynotes://search`
// (placeholder scheme until the final bundle id is chosen).

/// Routes app URLs (`stickynotes://…`) to app actions.
public enum DeepLinkRouter {

    public enum Action: Sendable, Equatable {
        case openNote(UUID)
        case newNote
        case search
    }

    /// Parses a deep link into an action. Unknown/malformed links are
    /// ignored (no crash).
    public static func action(for url: URL) -> Action? {
        guard url.scheme == "stickynotes" else { return nil }
        switch url.host {
        case "note":
            guard let raw = url.pathComponents.dropFirst().first,
                  let id = UUID(uuidString: raw) else { return nil }
            return .openNote(id)
        case "new":
            return .newNote
        case "search":
            return .search
        default:
            return nil
        }
    }

    /// The canonical URL for a note (used by widgets).
    public static func noteURL(_ id: UUID) -> URL {
        URL(string: "stickynotes://note/\(id.uuidString)")!
    }

    public static let newNoteURL = URL(string: "stickynotes://new")!
    public static let searchURL = URL(string: "stickynotes://search")!
}
