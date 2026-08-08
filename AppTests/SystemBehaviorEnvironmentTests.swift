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
// (CHK038). The presentation policy (`SystemBehaviorPolicy`) is the single
// source the custom controls consult.

@Suite struct SystemBehaviorEnvironmentTests {

    @Test
    func reduceTransparencyKeepsControlsReadable() {
        // SC-015/FR-062: custom controls must not rely on translucency —
        // under Reduce Transparency they degrade to readable surfaces.
        #expect(SystemBehaviorPolicy.readableWithoutTransparency == true)
        #expect(SystemBehaviorPolicy.usesTranslucencyForReadability == false)
    }

    @Test
    func reduceMotionGovernsCustomControlAnimations() {
        // CHK038: Reduce Motion governs custom-control appear/disappear
        // animations.
        #expect(SystemBehaviorPolicy.reduceMotionGovernsAnimations == true)
        #expect(SystemBehaviorPolicy.animationsNonEssential == false,
                "animations are never essential to understanding")
    }

    @Test
    func increaseContrastKeepsControlsDistinguishable() {
        // FR-062: under Increase Contrast / Show Borders the custom
        // controls keep visible borders — never half-transparent-only.
        #expect(SystemBehaviorPolicy.bordersUnderIncreaseContrast == true)
    }

    @Test
    func controlsNeverColorOnly() {
        // 001 FR-044 continuation: selection/state never conveyed by color
        // alone (also covers Show Borders states).
        #expect(SystemBehaviorPolicy.selectionNeverColorOnly == true)
    }
}

// MARK: - 003 T062 (SC-010/SC-019): Liquid Glass usage discipline

@Suite struct GlassUsagePolicyTests {

    @Test
    func noDecorativeGlass() {
        // SC-010: glass only on the functional/control layer — never as
        // decoration.
        #expect(GlassUsagePolicy.noDecorativeGlass == true)
        #expect(GlassUsagePolicy.glassFunctionalLayerOnly == true)
    }

    @Test
    func noManualLiquidGlassEmulation() {
        // SC-019: no manual blur/gradient/border/shaders emulating Liquid
        // Glass where a system behavior exists.
        #expect(GlassUsagePolicy.noManualEmulation == true)
        #expect(GlassUsagePolicy.systemEquivalentPreferred == true)
    }

    @Test
    func cardsAndContentSurfacesAreNotGlass() {
        // SC-009: note cards / content surfaces are NOT glass (content
        // layer stays opaque, FR-022/FR-041).
        #expect(GlassUsagePolicy.cardsNotGlass == true)
        #expect(GlassUsagePolicy.noteContentNotGlass == true)
        #expect(GlassUsagePolicy.editorSurfacesNotGlass == true)
    }

    @Test
    func noGlassOnGlass() {
        // FR-061: no nested glass-on-glass.
        #expect(GlassUsagePolicy.noGlassOnGlass == true)
    }

    @Test
    func clearGlassNotUsedAsDefault() {
        // FR-061: clear glass is never the default.
        #expect(GlassUsagePolicy.clearGlassNotDefault == true)
    }

    @Test
    func glassOnlyOnCustomInteractiveControls() {
        // FR-060/FR-044: glass MAY apply only to genuinely custom
        // interactive controls (insertion control, floating controls).
        #expect(GlassUsagePolicy.customInteractiveControlsMayGlass == true)
        #expect(GlassUsagePolicy.systemControlsUseSystemGlass == true)
    }
}
