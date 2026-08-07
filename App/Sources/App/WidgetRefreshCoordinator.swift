import Foundation
import WidgetKit
import Domain

// MARK: - WidgetRefreshCoordinator (T237, FR-110a)
//
// Per tasks.md T237 and spec FR-110a (clarified 2026-08-07): the main
// application proactively triggers a WidgetKit timeline reload for the
// AFFECTED widget kinds whenever local data affecting a widget changes
// (note created/edited/deleted/trashed/restored, todo toggled, widget-
// eligibility changed, conflict copy created). Widgets NEVER poll on a
// fixed high-frequency schedule (SC-006). Widget actions (todo toggle,
// quick-create) also trigger refresh of affected widgets.

/// Change-driven widget refresh (FR-110a).
public enum WidgetRefreshCoordinator {

    /// The widget kinds the app can reload (matches WidgetExtension).
    public enum Kind: String, Sendable, CaseIterable {
        case smallSelected = "StickyWidgetSmallSelected"
        case smallRecent = "StickyWidgetSmallRecent"
        case mediumMulti = "StickyWidgetMediumMulti"
        case mediumTodo = "StickyWidgetMediumTodo"
        case largeOverview = "StickyWidgetLargeOverview"
        case quickCreate = "StickyWidgetQuickCreate"
    }

    /// The kind of local change that may affect widgets (FR-110a).
    public enum Change: Sendable {
        case noteCreatedEditedDeletedTrashedRestored
        case todoToggled
        case eligibilityChanged
        case conflictCopyCreated
    }

    /// Reloads only the affected kinds (never a blanket reload of
    /// unaffected kinds — FR-110a). Tests may override the reload sink.
    /// `nonisolated(unsafe)`: a test-only seam; production code never
    /// mutates it (main-actor access pattern).
    public nonisolated(unsafe) static var reloadOverride: (([Kind]) -> Void)?

    public static func reload(_ kinds: [Kind]) {
        if let reloadOverride {
            reloadOverride(kinds)
            return
        }
        for kind in kinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind.rawValue)
        }
    }

    /// Routes a change to the affected widget kinds.
    public static func reload(for change: Change) {
        switch change {
        case .noteCreatedEditedDeletedTrashedRestored:
            reload(kindsAffectedByNoteChange())
        case .todoToggled:
            reload(kindsAffectedByTodoToggle())
        case .eligibilityChanged:
            reload(kindsAffectedByEligibilityChange())
        case .conflictCopyCreated:
            reload(kindsAffectedByConflictCopy())
        }
    }

    // MARK: - Change mapping (which events touch which kinds)

    public static func kindsAffectedByNoteChange() -> [Kind] {
        [.smallRecent, .mediumMulti, .largeOverview, .quickCreate]
    }

    public static func kindsAffectedByTodoToggle() -> [Kind] {
        [.mediumTodo, .mediumMulti, .largeOverview]
    }

    public static func kindsAffectedByEligibilityChange() -> [Kind] {
        [.smallSelected, .mediumMulti, .largeOverview, .quickCreate]
    }

    public static func kindsAffectedByConflictCopy() -> [Kind] {
        [.largeOverview, .mediumMulti]
    }
}
