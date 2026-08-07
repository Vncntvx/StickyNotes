import SwiftUI
import Domain

// MARK: - ConflictCopyView (T171, US10)
//
// Per tasks.md T171 and spec FR-170/FR-171/FR-172/FR-175: conflict-copy
// labeling + distinguishability in the library/Trash. A conflict copy is a
// note with `lifecycleState == .conflictCopy`, a `conflictOriginNoteId`,
// and a `conflictLabel`. It behaves as an active note but is clearly
// distinguishable (FR-175).

/// A badge shown on conflict-copy cards (FR-175 distinguishability).
public struct ConflictCopyBadge: View {
    let label: String?

    public init(label: String?) {
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
            Text(label ?? "Conflict copy")
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.yellow.opacity(0.2), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conflict copy: \(label ?? "recovered version")")
    }
}

/// Helper for library/Trash views: identifies conflict copies and their
/// origin labels (FR-172: origin/time label preserved on the card).
public enum ConflictCopyPresentation {
    /// The label to show for a note (conflict label for conflict copies).
    public static func badgeLabel(for note: Note) -> String? {
        note.lifecycleState == .conflictCopy ? note.conflictLabel : nil
    }

    /// Whether the note is distinguishable as a conflict copy.
    public static func isConflictCopy(_ note: Note) -> Bool {
        note.lifecycleState == .conflictCopy
    }
}
