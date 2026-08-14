import Foundation

// MARK: - NoteLifecycle state machine (T079)
//
// Per tasks.md T079 and data-model.md §Note lifecycle / §Tombstone lifecycle:
//
// - active → trashed (delete) → permanentlyDeleted (30-day expiry or manual
//   purge).
// - trashed → active (restore).
// - delete-vs-edit sync conflict → conflictCopy (recovered).
// - 30-day retention: trashed notes are recoverable for 30 days; after that
//   they are permanently deleted (readable content removed, tombstone
//   retained for sync-safety).
// - Empty-note auto-discard (FR-018/FR-019): a note that NEVER had content
//   is auto-discarded on close; a note that PREVIOUSLY had content is NOT
//   auto-deleted when its text becomes empty. The rule is `NoteAutoDiscard`
//   in this file (R1.8, remediation roadmap 2026-08-14: it previously
//   lived in NoteLifecycleTests.swift — production behavior that was
//   tested but never shipped, while the App duplicated a partial copy).
//
// Constitution VIII: tombstones are retained until sync-safety allows purge
// (not a hard wall-clock purge that could resurrect a note). Constitution X:
// close≠delete; 30-day Trash recovery.

// MARK: - Lifecycle transitions

/// The lifecycle transitions a note can undergo. The repository applies
/// these to the Note row + (for permanent delete) inserts a Tombstone.
public enum NoteLifecycleTransition: Sendable, Equatable {
    case trash           // active → trashed
    case restore         // trashed → active
    case permanentlyDelete  // trashed → permanentlyDeleted (+ tombstone)
    case markConflictCopy    // any → conflictCopy (sync recovery)
}

// MARK: - NoteLifecycle machine

/// Pure-Domain lifecycle state machine. Validates transitions and computes
/// 30-day expiry. No DB access — the repository calls these to decide
/// whether a transition is legal and to compute the resulting state.
public enum NoteLifecycle {

    /// The Trash retention window (30 days). Trashed notes older than this
    /// are eligible for permanent purge (sync-safety-gated; the actual
    /// purge is gated on tombstone sync state per constitution VIII).
    public static let trashRetentionDays: Int = 30

    /// Returns `true` if the transition is legal from the given state.
    public static func canTransition(
        from current: NoteLifecycleState,
        _ transition: NoteLifecycleTransition
    ) -> Bool {
        switch (current, transition) {
        case (.active, .trash): return true
        case (.trashed, .restore): return true
        case (.trashed, .permanentlyDelete): return true
        case (_, .markConflictCopy): return true  // any state can become a conflict copy via sync recovery
        default: return false
        }
    }

    /// Returns the resulting state after a transition. Returns `nil` if the
    /// transition is illegal from the given state.
    public static func apply(
        _ transition: NoteLifecycleTransition,
        to current: NoteLifecycleState,
        now: Date = Date()
    ) -> (state: NoteLifecycleState, trashedAt: Date?)? {
        guard canTransition(from: current, transition) else { return nil }
        switch transition {
        case .trash:
            return (.trashed, now)
        case .restore:
            return (.active, nil)
        case .permanentlyDelete:
            return (.permanentlyDeleted, nil)  // trashedAt cleared on permanent delete
        case .markConflictCopy:
            return (.conflictCopy, nil)
        }
    }

    /// Returns `true` if a trashed note is past the 30-day retention window
    /// and is eligible for permanent purge. The actual purge is sync-safety-
    /// gated (constitution VIII) — this function only computes the time
    /// eligibility.
    public static func isEligibleForPurge(trashedAt: Date, now: Date = Date()) -> Bool {
        let elapsed = now.timeIntervalSince(trashedAt)
        let retention = TimeInterval(trashRetentionDays) * 24 * 60 * 60
        return elapsed >= retention
    }

    /// Returns the set of lifecycle states that are visible in the library
    /// by default (active + conflictCopy). Trashed and permanentlyDeleted
    /// notes are NOT in the default library view.
    public static var libraryVisibleStates: [NoteLifecycleState] {
        [.active, .conflictCopy]
    }

    /// Returns the set of lifecycle states visible in the Trash view
    /// (trashed only). permanentlyDeleted notes are gone from the UI; their
    /// tombstones live in the DB for sync.
    public static var trashVisibleStates: [NoteLifecycleState] {
        [.trashed]
    }

    /// Distinguishes the four lifecycle states for UI labeling (FR-014 /
    /// T125). Returns a stable, language-neutral identifier (the App layer
    /// localizes these for display).
    public static func distinguishabilityLabel(for state: NoteLifecycleState) -> String {
        switch state {
        case .active: return "active"
        case .trashed: return "trashed"
        case .permanentlyDeleted: return "permanentlyDeleted"
        case .conflictCopy: return "conflictCopy"
        }
    }
}

// MARK: - Trash expiry scan
//
// The repository runs a periodic expiry scan: find trashed notes past the
// 30-day window and permanently delete them (sync-safety-gated). The scan
// logic is a pure function of (trashedAt, now) so it's testable without DB.

public enum TrashExpiry {

    /// Returns the ids of trashed notes that are past the retention window.
    /// The caller (NoteRepository) permanently deletes these, gated on
    /// tombstone sync state.
    public static func notesEligibleForPurge(
        trashedNotes: [(id: UUID, trashedAt: Date)],
        now: Date = Date()
    ) -> [UUID] {
        trashedNotes
            .filter { NoteLifecycle.isEligibleForPurge(trashedAt: $0.trashedAt, now: now) }
            .map(\.id)
    }
}

// MARK: - Empty-note auto-discard (FR-018 / FR-019 / FR-012a)
//
// R1.8 (remediation roadmap 2026-08-14): migrated from the test target
// (NoteLifecycleTests.swift) where it was defined but never shipped. The
// App previously duplicated a partial copy (NoteWindowHostModel.isMeaningful,
// missing the FR-013 prior-version check) — it now delegates here.

/// Encodes the empty-note auto-discard rule. "Meaningful content" per
/// FR-012a = (a) at least one non-whitespace Unicode character in the title
/// field, OR (b) at least one non-whitespace Unicode character in any
/// rich-text block, OR (c) the presence of any
/// todo/image/screenshot/code-block/file-reference block regardless of text
/// length. A single character qualifies; whitespace-only does NOT qualify
/// (spaces, tabs, newlines, U+3000 ideographic space, etc.). A note that
/// PREVIOUSLY held meaningful content but is now emptied is NOT auto-deleted
/// (FR-013).
public enum NoteAutoDiscard {
    /// Returns `true` if the note contains meaningful content per FR-012a.
    /// A previously-content note (a block with a non-nil `parentVersionId`)
    /// is also considered to have had content (FR-013: not auto-deleted
    /// when emptied).
    public static func hadContent(_ note: Note, blocks: [Block]) -> Bool {
        // (a) title with a non-whitespace character.
        if let title = note.title, containsNonWhitespace(title) {
            return true
        }
        for block in blocks {
            switch block.payload {
            case .richText(let doc):
                // (b) non-whitespace text in a rich-text block.
                if containsNonWhitespace(doc.text) { return true }
                // Previously had content (FR-013): a block with a parent
                // version was non-empty in a prior version.
                if block.parentVersionId != nil { return true }
            case .todo(let todo):
                // (c) a todo block counts as content regardless of text
                // length (structural block). But also check its text.
                if containsNonWhitespace(todo.richText.text) { return true }
                if block.parentVersionId != nil { return true }
                // An empty todo block with no prior version still counts as
                // a structural block per FR-012a (c).
                return true
            case .code(let code):
                // (c) a code block counts as content; also check its text.
                if containsNonWhitespace(code.text) { return true }
                if block.parentVersionId != nil { return true }
                return true
            // Non-text blocks (fileRef, image, screenshot) count as content.
            case .fileReference, .image, .screenshot:
                return true
            }
        }
        return false
    }

    /// Returns `true` if the note should be auto-discarded on window close.
    /// Per FR-018/FR-019/FR-012a: only notes that NEVER had meaningful
    /// content are auto-discarded.
    public static func shouldAutoDiscard(_ note: Note, blocks: [Block]) -> Bool {
        // Trashed/permanentlyDeleted/conflictCopy notes are never auto-discarded.
        guard note.lifecycleState == .active else { return false }
        return !hadContent(note, blocks: blocks)
    }

    /// Returns `true` if the string contains at least one non-whitespace
    /// Unicode character. Whitespace includes spaces, tabs, newlines,
    /// U+3000 ideographic space, and all Unicode "White_Space" characters.
    private static func containsNonWhitespace(_ string: String) -> Bool {
        !string.allSatisfy { $0.isWhitespace }
    }
}
