import Foundation
import SwiftUI
import Observation
import Domain
import Persistence
import SystemBridge

// MARK: - LibraryModel (T159/T269)
//
// The menu-bar library's observable state: cards, search, sort, lifecycle
// (library/Trash), sync status, first-launch state (FR-014a), and the
// unified error surface (FR-011a: failures never crash, surface as a
// non-blocking localized status message, library stays usable + retry).

@MainActor
@Observable
public final class LibraryModel {
    /// Which list the library shows.
    public enum Scope: Sendable, Equatable {
        case library
        case trash
    }

    public struct NoteCardRow: Identifiable, Equatable {
        public let noteId: UUID
        public let title: String?
        public let summary: String?
        public let previewSource: String?
        public let colorKey: NoteColorKey
        public let modifiedAt: Date
        public let todoProgress: String?
        public let hasScreenshot: Bool
        public let hasImage: Bool
        public let hasFileReference: Bool
        public let isConflictCopy: Bool
        public let syncWarning: Bool

        public var id: UUID { noteId }
    }

    // MARK: - State

    public private(set) var cards: [NoteCardRow] = []
    public var scope: Scope = .library
    public var sort: NoteSortKey = .modified
    public var searchQuery: String = ""
    public var isSearching: Bool { !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Non-blocking status message (FR-011a / FR-141b); nil = no message.
    public private(set) var statusMessage: String?
    public private(set) var isError = false
    public private(set) var isLoading = false
    /// In-memory mirror of the onboarding-hint dismissal so the UI updates
    /// immediately when "Got it" is clicked (the UserDefaults write alone
    /// cannot trigger observation — FR-014a).
    public private(set) var onboardingHintDismissed = false

    // MARK: - Keyboard navigation (003 T012, FR-024)

    /// The keyboard-selected note id (arrow-key selection model, FR-024).
    /// Distinct from mouse hover; used by ⌘⌫ move-to-Trash and Return-open
    /// commands. nil = no selection (e.g. empty grid).
    public private(set) var keyboardSelection: UUID?

    /// A search-focus request (⌘F / searchAll / `stickynotes://search`):
    /// the library view consumes it to focus the native search field.
    public private(set) var searchFocusRequested = false

    // MARK: - Sync attention banner (003 T026 shell → T056 complete)

    /// The sync attention banner state machine (FR-010 dismiss/re-present
    /// semantics; driven by the sync coordinator's state).
    public let bannerState = SyncBannerStateModel()

    /// The banner presentation derived from the current sync state (nil =
    /// zero footprint, FR-007).
    public var bannerPresentation: SyncBannerPresentation? {
        bannerState.current
    }

    /// Refreshes the banner from the sync coordinator's current state
    /// (FR-012 mapping). Called on reload and on coordinator state changes.
    public func refreshBanner() {
        guard let coordinator = syncCoordinator else { return }
        guard let presentation = SyncStatusResolver.resolve(
            isConfigured: coordinator.isConfigured,
            lastErrorCode: coordinator.lastErrorCode,
            vaultLocked: false,
            hasOfflineChangesPending: coordinator.isInProgress,
            summary: .empty
        ) else {
            bannerState.clearAll()
            return
        }
        bannerState.present(category: presentation.category)
    }

    /// Dismisses the banner (FR-010: while the underlying state is
    /// unchanged the banner does not reappear).
    public func dismissBanner() {
        bannerState.dismiss()
    }

    /// Performs the banner's action (retry/unlock/…).
    public func performBannerAction() {
        guard let category = bannerState.current?.category else { return }
        switch category {
        case .cannotConnect:
            Task { await syncCoordinator?.manualSync() }
        default:
            break
        }
    }

    /// First-launch onboarding hint visibility (FR-014a).
    public var showOnboardingHint: Bool {
        let state = preferences.firstLaunchState
        return !state.hasCreatedFirstNote && !state.dismissed && !onboardingHintDismissed
    }

    public let preferences: LocalPreferences
    /// The composed services (internal — the App layer uses it for global
    /// shortcut wiring and window coordination).
    let environment: AppEnvironment
    /// The sync composition root (T284): drives the library's sync-status
    /// area with real configuration/state. Nil in tests without sync.
    public let syncCoordinator: SyncCoordinator?

    public init(
        environment: AppEnvironment,
        preferences: LocalPreferences = LocalPreferences(),
        syncCoordinator: SyncCoordinator? = nil
    ) {
        self.environment = environment
        self.preferences = preferences
        self.syncCoordinator = syncCoordinator ?? environment.syncCoordinator
    }

    // MARK: - Loading

    /// Refreshes the card grid. `animated` wraps the grid replacement in a
    /// SwiftUI transaction so deletions/restores (FR-014/FR-026) glide
    /// instead of snapping away; search/scope/refresh stay instant (the
    /// keystroke path must not animate every intermediate result set).
    public func reload(animated: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let lifecycle: NoteLifecycleState = scope == .trash ? .trashed : .active
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let noteIds: Set<UUID>?
            if !query.isEmpty {
                // FR-023/FR-023a (T283): search through the FTS SearchService
                // (matches titles, body, todos, code, file display names,
                // screenshot captions — FR-023) so results are NOT bounded by
                // the 500-card row limit (SC-005) and privacy-excluded notes
                // are never revealed (T042). Falls back to the in-memory
                // filter only before bootstrap.
                if let service = environment.persistence.searchService {
                    let results = try await (scope == .trash
                        ? service.searchTrashedNotes(query: query, limit: 1000)
                        : service.searchActiveNotes(query: query, limit: 1000))
                    noteIds = Set(results.map(\.id))
                } else {
                    noteIds = nil
                }
            } else {
                noteIds = nil
            }
            // An empty FTS result set is an empty grid (FR-014c empty-state),
            // never an unfiltered list.
            if let noteIds, noteIds.isEmpty {
                cards = []
                return
            }
            var fetched = try await environment.persistence.fetchCards(
                lifecycle: lifecycle,
                sort: sort,
                noteIds: noteIds
            )
            if !query.isEmpty && noteIds == nil {
                // FR-024a prompt updates: in-memory fallback before the
                // search service exists (pre-bootstrap only).
                fetched = fetched.filter { card in
                    (card.title ?? "").localizedCaseInsensitiveContains(query)
                        || (card.generatedSummary ?? "").localizedCaseInsensitiveContains(query)
                        || (card.previewSource ?? "").localizedCaseInsensitiveContains(query)
                }
            }
            let rows = fetched.map { row in
                NoteCardRow(
                    noteId: row.noteId,
                    title: row.title,
                    summary: row.generatedSummary,
                    previewSource: row.previewSource,
                    colorKey: row.colorKey,
                    modifiedAt: row.modifiedAt,
                    todoProgress: row.todoProgressString,
                    hasScreenshot: row.hasScreenshot,
                    hasImage: row.hasImage,
                    hasFileReference: row.hasFileReference,
                    isConflictCopy: row.isConflictCopy,
                    syncWarning: row.syncWarning
                )
            }
            if animated {
                withAnimation(.snappy(duration: 0.25)) { cards = rows }
            } else {
                cards = rows
            }
        } catch {
            // FR-011a: never crash; non-blocking sanitized status.
            statusMessage = String(localized: "Could not load notes.")
            isError = true
        }
    }

    // MARK: - Sort + search

    public func setSort(_ newSort: NoteSortKey) {
        guard newSort != sort else { return }
        sort = newSort
        Task { await reload() }
    }

    public func setSearchQuery(_ query: String) {
        searchQuery = query
        Task { await reload() }
    }

    public func setScope(_ newScope: Scope) {
        guard newScope != scope else { return }
        scope = newScope
        searchQuery = ""
        keyboardSelection = nil
        Task { await reload() }
    }

    // MARK: - Keyboard navigation (003 T012/T027, FR-024)

    /// Selects the next/previous card in the current sort order (arrow
    /// keys). Wraps around at the ends. No-op on an empty grid.
    public func moveKeyboardSelection(by delta: Int) {
        guard !cards.isEmpty else { return }
        guard let current = keyboardSelection, let index = cards.firstIndex(where: { $0.noteId == current }) else {
            keyboardSelection = cards[0].noteId
            return
        }
        let next = (index + delta + cards.count) % cards.count
        keyboardSelection = cards[next].noteId
    }

    /// Clears the keyboard selection (grid emptied or scope switched).
    public func clearKeyboardSelection() {
        keyboardSelection = nil
    }

    /// Requests search focus (⌘F / searchAll / deep link, 003 T025).
    public func setSearchFocusRequested(_ requested: Bool) {
        searchFocusRequested = requested
    }

    // MARK: - Actions

    /// Dismisses the first-launch onboarding hint (FR-014a). Updates the
    /// observable state so the hint disappears immediately.
    public func dismissOnboardingHint() {
        preferences.dismissOnboardingHint()
        onboardingHintDismissed = true
    }

    /// Creates a blank note (FR-010) and returns its id, or nil on failure.
    public func createBlankNote() async -> UUID? {
        guard let repo = environment.persistence.noteRepository else { return nil }
        do {
            let note = Note(lastModifiedDeviceId: DeviceIdentity.current.id)
            try await repo.create(note)
            // The note's primary editing surface: insert the initial
            // (empty) rich-text block so typing persists from the first
            // keystroke. Without it the editor's commit path finds no
            // rich-text block and drops all input (verified 2026-08-07),
            // and the FR-012a close-time auto-discard removes the note.
            let block = Block(
                noteId: note.id,
                kind: .richText,
                sortKey: 0,
                payload: .richText(.empty),
                lastModifiedDeviceId: DeviceIdentity.current.id
            )
            try await repo.insert(block)
            preferences.markFirstNoteCreated()
            onboardingHintDismissed = true
            await reload()
            notifyWidgetsOfNoteChange()
            return note.id
        } catch {
            statusMessage = String(localized: "Could not create a note.")
            isError = true
            return nil
        }
    }

    /// Moves a note to Trash (FR-014). Returns the trashed note title for
    /// the FR-009a deletion toast.
    public func trash(noteId: UUID) async -> String? {
        guard let repo = environment.persistence.noteRepository else { return nil }
        do {
            let title = try await repo.fetch(id: noteId)?.title
            try await repo.trash(id: noteId, deviceId: DeviceIdentity.current.id)
            await reload(animated: true)
            notifyWidgetsOfNoteChange()
            return title
        } catch {
            statusMessage = String(localized: "Could not move the note to Trash.")
            isError = true
            return nil
        }
    }

    /// Restores a note from Trash (FR-014).
    public func restore(noteId: UUID) async {
        guard let repo = environment.persistence.noteRepository else { return }
        do {
            try await repo.restore(id: noteId, deviceId: DeviceIdentity.current.id)
            await reload(animated: true)
            notifyWidgetsOfNoteChange()
        } catch {
            statusMessage = String(localized: "Could not restore the note.")
            isError = true
        }
    }

    /// Permanently deletes a note (FR-014). Returns the deleted title.
    public func permanentlyDelete(noteId: UUID) async -> String? {
        guard let repo = environment.persistence.noteRepository else { return nil }
        do {
            let title = try await repo.fetch(id: noteId)?.title
            try await repo.permanentlyDelete(id: noteId, deviceId: DeviceIdentity.current.id)
            await reload(animated: true)
            notifyWidgetsOfNoteChange()
            return title
        } catch {
            statusMessage = String(localized: "Could not delete the note.")
            isError = true
            return nil
        }
    }

    /// Empty Trash (FR-014b): batch permanent delete with explicit
    /// confirmation (the CONFIRMATION lives in the view; the model performs
    /// the batch).
    public func emptyTrash() async -> Int {
        guard let repo = environment.persistence.noteRepository else { return 0 }
        do {
            let ids = try await repo.emptyTrash(deviceId: DeviceIdentity.current.id)
            await reload(animated: true)
            notifyWidgetsOfNoteChange()
            return ids.count
        } catch {
            statusMessage = String(localized: "Could not empty Trash.")
            isError = true
            return 0
        }
    }

    /// FR-110a (T294): widget-affecting library mutations trigger the
    /// change-driven widget refresh (WidgetRefreshCoordinator).
    private func notifyWidgetsOfNoteChange() {
        WidgetRefreshCoordinator.reload(for: .noteCreatedEditedDeletedTrashedRestored)
    }

    public func dismissStatusMessage() {
        statusMessage = nil
        isError = false
    }
}
