import Testing
import Foundation
import Domain

// MARK: - FirstLaunchState tests (T203, FR-014a clarified 2026-08-07)
//
// Per tasks.md T203: FirstLaunchState returns shouldShowOnboardingHint == true
// on a fresh state (seen=false, dismissed=false, hasCreatedFirstNote=false);
// returns false once hasCreatedFirstNote is set (never shown again after the
// first note is created); returns false once dismissed is set; returns false
// when dismissed even if seen; the state never carries sync/canonical-JSON
// exposure (pure value type, no UserDefaults dependency).

@Suite struct FirstLaunchStateTests {

    @Test
    func freshStateShowsOnboardingHint() {
        let state = FirstLaunchState.fresh
        #expect(state.shouldShowOnboardingHint)
    }

    @Test
    func defaultInitIsFresh() {
        let state = FirstLaunchState()
        #expect(state.seen == false)
        #expect(state.dismissed == false)
        #expect(state.hasCreatedFirstNote == false)
        #expect(state.shouldShowOnboardingHint)
    }

    @Test
    func creatingFirstNoteHidesHintPermanently() {
        var state = FirstLaunchState.fresh
        state.markFirstNoteCreated()
        #expect(!state.shouldShowOnboardingHint)
        // Even after marking seen, it stays hidden.
        state.markSeen()
        #expect(!state.shouldShowOnboardingHint)
    }

    @Test
    func dismissingHidesHintPermanently() {
        var state = FirstLaunchState.fresh
        state.dismiss()
        #expect(!state.shouldShowOnboardingHint)
        // Even if hasCreatedFirstNote is later reset (shouldn't happen, but
        // the state machine is defensive), dismissed stays dismissed.
        #expect(state.dismissed)
    }

    @Test
    func dismissedHidesHintEvenIfSeen() {
        var state = FirstLaunchState.fresh
        state.markSeen()
        #expect(state.shouldShowOnboardingHint, "seen alone does not hide the hint")
        state.dismiss()
        #expect(!state.shouldShowOnboardingHint, "dismissed hides even if seen")
    }

    @Test
    func markSeenDoesNotDismiss() {
        var state = FirstLaunchState.fresh
        state.markSeen()
        #expect(state.seen)
        #expect(!state.dismissed)
        #expect(state.shouldShowOnboardingHint, "seen without dismiss/first-note still shows")
    }

    @Test
    func stateIsPureValueTypeNoUserDefaultsDependency() {
        // The FirstLaunchState is a pure Foundation value type — no
        // UserDefaults, no App Group, no sync/canonical-JSON exposure.
        // Verify it's Codable (for potential App-layer persistence) and
        // Sendable.
        let state = FirstLaunchState(seen: true, dismissed: false, hasCreatedFirstNote: true)
        // Codable round-trip.
        let data = try? JSONEncoder().encode(state)
        #expect(data != nil)
        let decoded = try? JSONDecoder().decode(FirstLaunchState.self, from: data!)
        #expect(decoded == state)
        // Sendable (compiles).
        func _sendable<T: Sendable>(_ x: T) {}
        _sendable(state)
    }

    @Test
    func stateEqualityIsValueBased() {
        let a = FirstLaunchState(seen: true, dismissed: false, hasCreatedFirstNote: false)
        let b = FirstLaunchState(seen: true, dismissed: false, hasCreatedFirstNote: false)
        #expect(a == b)
        var c = a
        c.markFirstNoteCreated()
        #expect(a != c)
    }
}
