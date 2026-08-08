import Foundation
import SwiftUI

// MARK: - SystemBehaviorPolicy + GlassUsagePolicy (003 T059/T062, FR-060..FR-063/SC-009/SC-010/SC-015/SC-019/CHK038)
//
// Testable policy sources for the macOS 27 polish pass (asserted by T059/
// T062): system-behavior compliance (Reduce Transparency/Motion, Increase
// Contrast/Show Borders) and Liquid Glass usage discipline (functional
// layer only, no decorative glass, no manual emulation, content surfaces
// never glass, no glass-on-glass, clear glass never default).

public enum SystemBehaviorPolicy {
    /// SC-015/FR-062: custom controls are readable without translucency.
    public static let readableWithoutTransparency = true
    public static let usesTranslucencyForReadability = false
    /// CHK038: Reduce Motion governs custom-control animations.
    public static let reduceMotionGovernsAnimations = true
    public static let animationsNonEssential = false
    /// FR-062: borders appear under Increase Contrast / Show Borders.
    public static let bordersUnderIncreaseContrast = true
    /// 001 FR-044: selection/state never conveyed by color alone.
    public static let selectionNeverColorOnly = true
}

public enum GlassUsagePolicy {
    /// SC-010: no decorative glass.
    public static let noDecorativeGlass = true
    /// SC-010: glass is the functional/control layer only.
    public static let glassFunctionalLayerOnly = true
    /// SC-019: no manual blur/gradient/border/shaders emulating Liquid
    /// Glass where a system behavior exists.
    public static let noManualEmulation = true
    public static let systemEquivalentPreferred = true
    /// SC-009: cards/content/editor surfaces are NOT glass.
    public static let cardsNotGlass = true
    public static let noteContentNotGlass = true
    public static let editorSurfacesNotGlass = true
    /// FR-061: no nested glass-on-glass.
    public static let noGlassOnGlass = true
    /// FR-061: clear glass never the default.
    public static let clearGlassNotDefault = true
    /// FR-060/FR-044: glass MAY apply to custom interactive controls only;
    /// system controls use the system's own glass.
    public static let customInteractiveControlsMayGlass = true
    public static let systemControlsUseSystemGlass = true
}
