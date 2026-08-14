import SwiftUI
import AppKit

// MARK: - BlockInsertionPolicy (003 T031, FR-043/SC-004/CHK008)
//
// Per tasks.md T031 and spec FR-043/SC-004: the presentation policy for
// block insertion — a subtle insertion-point context control (near the
// cursor line), NO persistent "Add Block" first-screen control, menu
// commands + keyboard (⌘⇧T/⌘⇧C) preserved, NO "/" command system, and the
// control never obscures content. The policy is the single source the
// editor view consults (asserted by T029).

public enum BlockInsertionPolicy {

    /// SC-004: the persistent first-screen "Add Block" control is removed.
    public static let hasPersistentFirstScreenControl = false

    /// FR-043: the insertion-point context control is enabled (subtle,
    /// near the cursor line).
    public static let insertionPointContextControlEnabled = true

    /// SC-004: Edit/Insert menu commands expose block insertion (003 T011
    /// CommandGroups).
    public static let menuCommandsEnabled = true

    /// SC-004/001 FR-050: ⌘⇧T (todo) and ⌘⇧C (code) survive.
    public static let keyboardShortcutPreserved = true

    /// FR-043: the context control appears only when useful and never
    /// obscures content.
    public static let obscuresContent = false

    /// FR-043 (clarify 2): no "/" command system.
    public static let slashCommandEnabled = false

    /// CHK008: concrete presentation triggers — the control appears when
    /// the cursor line is hovered or the selection is active, and hides on
    /// pointer leave / blur / active IME composition.
    public static let appearsOnCursorLineHover = true
    public static let appearsOnSelection = true
    public static let hidesOnPointerLeave = true
    public static let hidesOnBlur = true
    public static let hidesDuringIMEComposition = true
}

// MARK: - BlockInsertionControl (003 T031, FR-043)

/// A subtle insertion-point context control: a small "+" affordance near
/// the cursor line offering block insertion (todo/code/file/capture).
/// Native presentation (glassEffect MAY per FR-044/FR-061 — applied in the
/// US6 polish pass); appears only when useful (cursor-line hover or
/// selection), hides on pointer leave/blur/IME (CHK008), and never
/// obscures content.
public struct BlockInsertionControl: View {
    let onInsertTodo: () -> Void
    let onInsertCode: () -> Void
    let onInsertFileReference: () -> Void
    let onCaptureScreenshot: () -> Void

    /// CHK008 presentation triggers (drives the overlay visibility).
    @Binding var isCursorLineHovered: Bool
    @Binding var isTextSelected: Bool
    @Binding var isIMEComposing: Bool

    public init(
        onInsertTodo: @escaping () -> Void = {},
        onInsertCode: @escaping () -> Void = {},
        onInsertFileReference: @escaping () -> Void = {},
        onCaptureScreenshot: @escaping () -> Void = {},
        isCursorLineHovered: Binding<Bool> = .constant(false),
        isTextSelected: Binding<Bool> = .constant(false),
        isIMEComposing: Binding<Bool> = .constant(false)
    ) {
        self.onInsertTodo = onInsertTodo
        self.onInsertCode = onInsertCode
        self.onInsertFileReference = onInsertFileReference
        self.onCaptureScreenshot = onCaptureScreenshot
        self._isCursorLineHovered = isCursorLineHovered
        self._isTextSelected = isTextSelected
        self._isIMEComposing = isIMEComposing
    }

    public var body: some View {
        // 004 修复 (2026-08-14, P0): the control ALWAYS exists at a fixed
        // size — visibility is opacity + hit testing only, so it never
        // participates in the document's vertical flow (the host places it
        // in an overlay): showing/hiding must not move a single frame.
        let shown = BlockInsertionPolicy.insertionPointContextControlEnabled
            && visible
            && !BlockInsertionPolicy.obscuresContent
        Menu {
            Button("Add Todo", action: onInsertTodo)
            Button("Add Block", action: onInsertCode)
            Divider()
            Button("Add File Reference…", action: onInsertFileReference)
            Button("Capture Screenshot…", action: onCaptureScreenshot)
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(3)
                // 003 T064 (FR-060/FR-061): glass MAY apply to genuinely
                // custom interactive controls (plan.md §7 Usage Map).
                // System glass auto-degrades under Reduce Transparency
                // (SC-015); no glass-on-glass; clear glass is never the
                // default. Guarded: macOS 26.0+ availability.
                .background(GlassUsagePolicy.customInteractiveControlsMayGlass ? AnyView(glassBackground) : AnyView(circleBackground))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .help("Insert a block")
        .accessibilityLabel("Insert block")
    }

    /// The glass background (macOS 26.0+ — the deployment floor, so no
    /// availability guard is needed at compile time; the runtime handles
    /// Reduce Transparency automatically). 2026-08-14 (T187 follow-up):
    /// the `.regularMaterial` fill is restored under the glass — a bare
    /// `glassEffect` circle floats nearly invisible over note paper (same
    /// regression as the format bar); the material keeps the control
    /// visible while glassEffect adds the Liquid Glass finish.
    @ViewBuilder
    private var glassBackground: some View {
        if #available(macOS 26.0, *) {
            Circle()
                .fill(.regularMaterial)
                .glassEffect(.regular, in: Circle())
        } else {
            Circle().fill(.regularMaterial)
        }
    }

    private var circleBackground: some View {
        Circle().fill(.regularMaterial)
    }

    /// CHK008: visible only when a trigger is active and no IME
    /// composition is in progress.
    private var visible: Bool {
        !isIMEComposing
            && !BlockInsertionPolicy.hidesOnBlur  // blur handled by host binding
            && (isCursorLineHovered || isTextSelected)
    }
}

// MARK: - NoteControlsPresentation (003 T033, FR-044/FR-045/FR-064)

/// The floating note-controls presentation model: inactive-state behavior
/// (FR-045), glass scoping (FR-044/061), hide-on-pointer-leave, SF Symbols
/// only (FR-064). Asserted by T030.
public enum NoteControlsPresentation {

    /// FR-045: no inappropriate accent retention on inactive controls.
    public static let showsAccentWhenInactive = false

    /// FR-044: floating controls hide when the window is inactive.
    public static let floatingControlsHideWhenInactive = true

    /// FR-044: floating controls hide on pointer leave.
    public static let floatingControlsHideOnPointerLeave = true

    /// FR-064: icons are SF Symbols only (never custom bitmaps).
    public static let usesSFSymbolsOnly = true
}
