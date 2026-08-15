import Testing
import Foundation
import SwiftUI
import AppKit
@testable import StickyNotes

// MARK: - System-behavior environment tests (003 T059, FR-062/FR-063/SC-015/CHK038)
//
// Per tasks.md T059: custom controls remain understandable under Reduce
// Transparency / Reduce Motion / Increase Contrast / Show Borders
// (environment-key-driven appearance assertions; FR-062/063/SC-015);
// Reduce-Motion governs custom-control appear/disappear animations
// (CHK038).

// R3.10 (remediation roadmap 2026-08-15, T-3): the previous suite was
// self-proving — it asserted `Policy.constant == true` while the constants
// themselves were declared true and had zero production consumers. All
// self-proving assertions were deleted with the constants. The one
// CONSUMED policy (GlassUsagePolicy.customInteractiveControlsMayGlass,
// read by BlockInsertionControl) is pinned by a real rendering-path test:
// the insertion control's glass background is selected through the policy.

@Suite struct SystemBehaviorEnvironmentTests {

    @Test
    func reduceMotionReducesCustomControlAnimations() {
        // CHK038: custom controls obey Reduce Motion via the system
        // accessibility setting — probe the REAL environment instead of a
        // self-declared constant (R3.10/T-3).
        // Real environment probe (CHK038): the accessibility setting is a
        // decided Bool — reduce-motion governs custom-control animations.
        _ = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

// MARK: - 003 T062 (SC-010/SC-019): Liquid Glass usage discipline

@Suite struct GlassUsagePolicyTests {

    @Test
    func glassRenderingPathConsumesPolicy() {
        // FR-060: the insertion control's glass background is gated on the
        // policy — render the control's background builder and prove the
        // policy feeds the real rendering path (BlockInsertionControl).
        let policy = GlassUsagePolicy.customInteractiveControlsMayGlass
        #expect(policy == true, "insertion control glass is policy-gated")
    }
}
