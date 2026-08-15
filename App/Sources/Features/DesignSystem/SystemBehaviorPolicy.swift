import Foundation
import SwiftUI

// MARK: - SystemBehaviorPolicy + GlassUsagePolicy (003 T059/T062, FR-060..FR-063/SC-009/SC-010/SC-015/SC-019/CHK038)
//
// Testable policy sources for the macOS 27 polish pass (asserted by T059/
// T062): system-behavior compliance (Reduce Transparency/Motion, Increase
// Contrast/Show Borders) and Liquid Glass usage discipline (functional
// layer only, no decorative glass, no manual emulation, content surfaces
// never glass, no glass-on-glass, clear glass never default).

// R3.10 (remediation roadmap 2026-08-15, T-3): the policy tables were
// self-proving — every constant declared true and tests asserted the
// declaration, with ZERO production consumers (audited 2026-08-15). All
// constants except `customInteractiveControlsMayGlass` (consumed by
// BlockInsertionControl) were deleted; the design discipline lives in the
// review checklist (specs/001 plan.md) and the GlassUsagePolicy
// consumption test.

public enum GlassUsagePolicy {
    /// FR-060/FR-044: glass MAY apply to custom interactive controls only;
    /// system controls use the system's own glass. Consumed by
    /// BlockInsertionControl (the insertion control's glass background).
    public static let customInteractiveControlsMayGlass = true
}
