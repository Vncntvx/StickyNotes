import Foundation
import Domain

// MARK: - AutoSave draft manager (T031)
//
// Per tasks.md T031 and plan §Auto-save:
//
// - Local-first. In-memory draft per open note; debounce ordinary text
//   persistence ~300 ms; save structural ops + todo completion immediately;
//   flush on focus loss, before window close, before termination; never wait
//   for remote sync to consider a local save complete.
// - Stale-debounced-write protection via revision tokens / serialized
//   note-edit sessions.
//
// This is the framework-free, testable core. The App layer wraps it with a
// main-actor `@Observable` model that hooks into focus/window-close/terminate
// notifications and feeds real Block snapshots in. Constitution XII: tests
// are mandatory (AutoSaveTests.swift).
//
// Concurrency: the manager is a value-typed configuration + a small actor
// that owns the mutable pending state. The actor boundary means UI-side
// callers hop to the actor for mutations; the save sink runs on the actor
// (off the main actor — plan §Never on Main Actor for persistence writes).

/// An opaque, monotonically increasing token identifying a draft revision.
/// Used to drop stale debounced writes: when a structural op (immediate
/// save) advances the token, a previously-scheduled debounced write that
/// carries an older token is discarded instead of clobbering newer state.
public struct AutoSaveRevisionToken: Hashable, Sendable, Comparable {
    public let value: UInt64
    public init(_ value: UInt64) { self.value = value }
    public static func < (lhs: AutoSaveRevisionToken, rhs: AutoSaveRevisionToken) -> Bool {
        lhs.value < rhs.value
    }
}

/// The save sink signature: receives the note id, the revision token this
/// save represents, and the snapshot of blocks to persist.
public typealias AutoSaveSink = @Sendable (UUID, AutoSaveRevisionToken, [Block]) async -> Void

/// The clock closure used by the manager to read the current time. Injecting
/// this makes the debounce window deterministic in tests.
public typealias AutoSaveClock = @Sendable () -> Date

/// Pending state for a debounced save. Carries the snapshot and the token
/// that must match at flush time for the write to proceed.
private struct PendingDraft: Sendable {
    let token: AutoSaveRevisionToken
    let blocks: [Block]
    let scheduledAt: Date
}

/// The auto-save draft manager. Owns one note's pending draft state.
///
/// - `textEdited`: ordinary text edits — debounced.
/// - `structuralChange`: block insert/delete/reorder, todo toggle, etc. —
///   saves immediately.
/// - `flushNow`: forces the pending debounced write to fire now (focus loss,
///   window close, terminate).
/// - `tick`: advances the debounce check; called by the App's timer (or by
///   tests directly).
public actor AutoSaveDraftManager {
    public nonisolated let noteId: UUID
    private let deviceId: UUID
    private let debounceInterval: TimeInterval
    private let now: AutoSaveClock
    private let save: AutoSaveSink

    /// Monotonic token; bumped on every accepted edit.
    private var currentToken: AutoSaveRevisionToken
    /// The pending debounced draft, if any. Structural ops and flushNow
    /// clear this.
    private var pending: PendingDraft?
    /// The last token that was actually saved (immediate or debounced).
    private var lastSavedToken: AutoSaveRevisionToken?

    public init(
        noteId: UUID,
        deviceId: UUID,
        debounceInterval: TimeInterval = 0.3,
        now: @escaping AutoSaveClock = { Date() },
        save: @escaping AutoSaveSink
    ) {
        self.noteId = noteId
        self.deviceId = deviceId
        self.debounceInterval = debounceInterval
        self.now = now
        self.save = save
        self.currentToken = AutoSaveRevisionToken(0)
        self.pending = nil
        self.lastSavedToken = nil
    }

    // MARK: - Edit entry points

    /// Ordinary text edit. Schedules a debounced save. Replaces any prior
    /// pending draft with the same token lineage (coalescing within the
    /// debounce window).
    public func textEdited(blocks: [Block]) {
        let token = bumpToken()
        pending = PendingDraft(token: token, blocks: blocks, scheduledAt: now())
    }

    /// Structural op (block insert/delete/reorder, todo toggle). Saves
    /// immediately and clears any pending debounced draft. The pending
    /// draft's token is now stale and will be dropped if it fires later.
    public func structuralChange(blocks: [Block]) async {
        let token = bumpToken()
        pending = nil
        await save(noteId, token, blocks)
        lastSavedToken = token
    }

    /// Forces any pending debounced draft to flush now (focus loss, window
    /// close, terminate). No-op if nothing is pending.
    public func flushNow() async {
        guard let pending = pending else { return }
        // Drop the pending draft before calling save so a concurrent tick
        // can't re-fire it.
        self.pending = nil
        await save(noteId, pending.token, pending.blocks)
        lastSavedToken = pending.token
    }

    // MARK: - Debounce driver

    /// Checks whether the pending draft's debounce window has elapsed and,
    /// if so, flushes it. Called by the App's timer (every ~50–100 ms) or
    /// by tests.
    public func tick() async {
        guard let pending = pending else { return }
        let elapsed = now().timeIntervalSince(pending.scheduledAt)
        guard elapsed >= debounceInterval else { return }
        // Token check: if a structural op advanced the token after this
        // draft was scheduled, drop the stale write.
        guard pending.token == currentToken else {
            self.pending = nil
            return
        }
        self.pending = nil
        await save(noteId, pending.token, pending.blocks)
        lastSavedToken = pending.token
    }

    // MARK: - State queries

    /// `true` if a debounced save is pending.
    public var hasPendingChanges: Bool { pending != nil }

    /// Clears any pending draft WITHOUT flushing. Used when the draft is
    /// discarded (e.g., the note was auto-discarded on close per FR-018).
    public func resetPending() {
        pending = nil
    }

    // MARK: - Internals

    private func bumpToken() -> AutoSaveRevisionToken {
        currentToken = AutoSaveRevisionToken(currentToken.value + 1)
        return currentToken
    }
}
