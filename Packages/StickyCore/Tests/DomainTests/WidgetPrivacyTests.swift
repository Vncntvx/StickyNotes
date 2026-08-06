import Testing
import Foundation
import Domain

// MARK: - Widget privacy tests (T095)
//
// Per tasks.md T095: "Domain test: widget-ineligible note exposes nothing in
// timelines/previews/placeholders/snapshots/logs" (research.md R14;
// constitution VI).

@Suite struct WidgetPrivacyTests {

    private func note(widgetEligible: Bool, lifecycle: NoteLifecycleState = .active, conflictOrigin: UUID? = nil) -> Note {
        Note(
            id: UUID(),
            title: "secret title",
            colorKey: .yellow,
            customColor: nil,
            transparency: 0.0,
            textSize: .regular,
            alwaysOnTop: false,
            widgetEligible: widgetEligible,
            coverScreenshotBlockId: nil,
            manualSortKey: 0,
            lifecycleState: lifecycle,
            trashedAt: nil,
            conflictOriginNoteId: conflictOrigin,
            conflictLabel: nil,
            versionId: UUID(),
            parentVersionId: nil,
            lastModifiedDeviceId: UUID(),
            createdAt: Date(),
            modifiedAt: Date()
        )
    }

    @Test
    func ineligibleNoteExposesNothing() {
        let ineligible = note(widgetEligible: false)
        let surface = WidgetVisibility.surface(for: ineligible)
        #expect(surface == .none, "an ineligible note must expose NOTHING (not even a placeholder)")
    }

    @Test
    func eligibleActiveNoteExposesContent() {
        let eligible = note(widgetEligible: true)
        let surface = WidgetVisibility.surface(for: eligible)
        #expect(surface == .content)
    }

    @Test
    func trashedOrDeletedNotesNeverExposeContent() {
        let trashed = note(widgetEligible: true, lifecycle: .trashed)
        #expect(WidgetVisibility.surface(for: trashed) == .placeholder)

        let deleted = note(widgetEligible: true, lifecycle: .permanentlyDeleted)
        #expect(WidgetVisibility.surface(for: deleted) == .placeholder)
    }

    @Test
    func conflictCopiesNeverExposeContent() {
        let conflicted = note(widgetEligible: true, conflictOrigin: UUID())
        #expect(WidgetVisibility.surface(for: conflicted) == .placeholder,
                "conflict copies must never be exposed via widgets (research.md R14)")
    }

    @Test
    func schemaMismatchYieldsPlaceholderNotContent() {
        let eligible = note(widgetEligible: true)
        let surface = WidgetVisibility.surface(for: eligible, schemaVersionKnown: false)
        #expect(surface == .placeholder, "schema mismatch must fall back to privacy-safe placeholders")
    }

    @Test
    func timelineAdmissionRequiresEligibility() {
        #expect(WidgetVisibility.mayAppearInTimelines(for: note(widgetEligible: true)))
        #expect(!WidgetVisibility.mayAppearInTimelines(for: note(widgetEligible: false)))
    }
}
