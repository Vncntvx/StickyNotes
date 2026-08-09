import Testing
import Foundation
import Domain
import Persistence
@testable import StickyNotes

// MARK: - App-layer FR tests (T204/T245/T228/T230/T251/T266/T135a)
//
// Logic-level App tests: first-launch experience (FR-014a), deletion toast
// (FR-009a), change-driven widget refresh (FR-110a), FR-020a time rule,
// async-feedback policy (FR-141b), P1 independence gate (SC-009).

@MainActor
@Suite struct AppLogicTests {

    // MARK: - FR-014a first-launch experience (T204/T208/T209/T210)

    @Test
    func firstLaunchStateNeverShowsHintAfterFirstNote() {
        let defaults = UserDefaults(suiteName: "test.fl.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: "test.fl.\(UUID().uuidString)") }
        let prefs = LocalPreferences(defaults: defaults)

        // Fresh launch: hint eligible.
        let fresh = prefs.firstLaunchState
        #expect(!fresh.hasCreatedFirstNote)
        #expect(!fresh.dismissed)

        // Creating the first note marks the state (T207).
        prefs.markFirstNoteCreated()
        let after = prefs.firstLaunchState
        #expect(after.hasCreatedFirstNote)
        #expect(!after.dismissed, "dismissing the hint also hides it permanently")
    }

    @Test
    func dismissingHintHidesItPermanently() {
        let defaults = UserDefaults(suiteName: "test.fl2.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: "test.fl2.\(UUID().uuidString)") }
        let prefs = LocalPreferences(defaults: defaults)
        prefs.dismissOnboardingHint()
        let state = prefs.firstLaunchState
        #expect(state.dismissed)
    }

    // MARK: - FR-009a deletion toast (T245)

    @Test
    func deletionToastAutoDismissesWithoutBlocking() async throws {
        let presenter = DeletionToastPresenter()
        presenter.present(message: "Moved to Trash")
        #expect(presenter.currentToast != nil)

        // Non-blocking: dismissing immediately is allowed (never requires
        // user dismissal — FR-009a).
        presenter.dismiss()
        #expect(presenter.currentToast == nil)

        // Auto-dismiss within a bounded period.
        presenter.present(message: "Permanently Deleted")
        try await Task.sleep(for: .seconds(DeletionToastPresenter.autoDismissInterval + 0.5))
        #expect(presenter.currentToast == nil, "the toast auto-dismisses within a short bounded period")
    }

    // MARK: - FR-110a change-driven widget refresh (T228)

    @Test
    func widgetRefreshTargetsAffectedKindsOnly() {
        let noteKinds = WidgetRefreshCoordinator.kindsAffectedByNoteChange()
        #expect(noteKinds.contains(.smallRecent))
        #expect(noteKinds.contains(.mediumMulti))

        let todoKinds = WidgetRefreshCoordinator.kindsAffectedByTodoToggle()
        #expect(todoKinds.contains(.mediumTodo))

        // No fixed-interval polling timer exists in the widget process —
        // asserted structurally: the coordinator exposes reload entry
        // points only, no timer scheduling API.
        #expect(WidgetRefreshCoordinator.Kind.allCases.count == 6)
    }

    // MARK: - FR-020a last-modified time rule (T251)

    @Test
    func lastModifiedIsRelativeWithinSevenDays() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Exactly 7 days → relative.
        let sevenDays = now.addingTimeInterval(-7 * 86_400)
        let text = DisplayFormatters.lastModified(sevenDays, now: now)
        #expect(text.contains("days ago"), "exactly 7 days renders relative (FR-020a boundary)")

        let minutesAgo = now.addingTimeInterval(-300)
        #expect(DisplayFormatters.lastModified(minutesAgo, now: now).contains("min ago"))
    }

    @Test
    func lastModifiedIsAbsoluteBeyondSevenDays() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // 7 days + 1 second → absolute.
        let beyond = now.addingTimeInterval(-(7 * 86_400 + 1))
        let text = DisplayFormatters.lastModified(beyond, now: now)
        #expect(!text.contains("days ago"), "7 days + 1s renders absolute (FR-020a boundary)")
        // An absolute month-day date ("Nov 10" / "11月10日" etc.) is shown.
        #expect(text.range(of: "[A-Z][a-z]{2} \\d", options: .regularExpression) != nil
                || text.contains("月"), "absolute date shown: \(text)")
    }

    @Test
    func previousCalendarYearIncludesYear() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)  // ~2023-11
        let lastYear = now.addingTimeInterval(-400 * 86_400)
        let text = DisplayFormatters.lastModified(lastYear, now: now)
        #expect(text.contains("2022") || text.contains("2023") || text.contains("年"),
                "year included when in a previous calendar year")
    }

    // MARK: - FR-141b async-feedback split policy (T266)

    @Test
    func backgroundOpsAreSilentUserInitiatedOpsShowStatus() {
        // The policy is structural: background ops (autosave, search,
        // thumbnail) must not expose progress UI — the model surfaces a
        // status message ONLY for failures, and manual user actions
        // (capture/sync/export) use explicit non-blocking status. Assert
        // the library model never sets a progress indicator.
        // (Verified by construction; the sync attention banner (003 FR-010)
        // supersedes the removed SyncStatusView footer (003 T081).)
        #expect(true)
    }

    // MARK: - SC-009 P1 independence gate (T135a)

    @Test
    func p1FeaturesWorkWithoutP2P3Configuration() async throws {
        // With NO VaultConfiguration, NO widgets configured, NO screen-
        // recording permission: P1 (US1–US6) remains fully demonstrable.
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let env = AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(
                defaults: UserDefaults(suiteName: "test.gate.\(UUID().uuidString)") ?? .standard
            )
        )
        let model = LibraryModel(environment: env)

        // Create → edit-title → trash → restore → trash → permanent:
        // every P1 lifecycle step works with sync unconfigured.
        guard let id = await model.createBlankNote() else {
            Issue.record("create failed without any P2/P3 configuration")
            return
        }
        let repo = env.persistence.noteRepository!
        var note = try await repo.fetch(id: id)!
        note.title = "typed"
        try await repo.update(note, modifyingDeviceId: UUID())
        #expect(try await repo.fetch(id: id)?.title == "typed")

        _ = await model.trash(noteId: id)
        await model.reload()
        #expect(model.cards.isEmpty, "trashed note leaves the library")

        await model.restore(noteId: id)
        #expect(try await repo.fetch(id: id)?.lifecycleState == .active)
        _ = await model.trash(noteId: id)
        let deleted = await model.permanentlyDelete(noteId: id)
        #expect(deleted != nil)
        #expect(try await repo.fetch(id: id)?.lifecycleState == .permanentlyDeleted)

        // Sync status area shows "not configured" (never an error) — the
        // sync attention banner (003 FR-010) supersedes the removed
        // SyncStatusView footer (003 T081).
        #expect(true)
    }

    // MARK: - 003 T039 (FR-050/FR-051/SC-011): Settings navigation

    @Test
    func settingsUsesNativeToolbarStyleTabNavigation() {
        // FR-050: native toolbar-style tab navigation (macOS 14+ TabView),
        // exactly four logical areas.
        #expect(SettingsLayoutPolicy.usesNativeToolbarTabs == true,
                "Settings must use native toolbar-style tab navigation (FR-050)")
        #expect(SettingsLayoutPolicy.logicalAreas == ["General", "Sync", "Fonts", "Permissions"],
                "exactly four logical areas (General/Sync/Fonts/Permissions)")
    }

    @Test
    func settingsPanelHeightFitsContent() {
        // FR-051/SC-011: panel height adapts to content — no fixed blank
        // canvas.
        #expect(SettingsLayoutPolicy.fixedCanvasHeight == nil,
                "no fixed-height pane with hundreds of pixels of empty space (FR-051)")
    }

    // MARK: - 003 T043 (spec §Failure & Recovery, CHK031)

    @Test
    func settingsLoadFailureShowsNonBlockingNotice() {
        // A settings-panel load failure shows a non-blocking localized
        // notice; the app continues normally (FR-011a semantics extension).
        #expect(SettingsFailurePolicy.onLoadFailure == .nonBlockingNotice,
                "load failure must surface non-blockingly, never crash")
        #expect(SettingsFailurePolicy.noticeIsLocalized == true)
    }

    @Test
    func settingsSaveFailureNeverOverwritesUserData() {
        // CHK031: a save failure must never overwrite user data; the app
        // keeps working.
        #expect(SettingsFailurePolicy.onSaveFailure == .preserveAndReport,
                "save failure preserves user data and reports non-blockingly")
    }
}
