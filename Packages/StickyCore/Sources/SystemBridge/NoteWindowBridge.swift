import Foundation
import AppKit
import Domain
import os

// MARK: - NoteWindowBridge (T160, T146)
//
// Per tasks.md T160 and plan §Application scenes: AppKit bridge for note
// windows — registration/focus/level, isolated in SystemBridge (all AppKit
// low-level APIs live here). T146 (FR-035): note windows do NOT appear
// across every Space and do NOT force over full-screen applications; both
// are configured via `NSWindow.collectionBehavior`.
//
// The registry is lock-guarded so the App layer (main actor) and any
// background flush paths can query it safely. Windows are tracked by note
// UUID; the App layer owns the actual `NSWindow` instances and hands them in
// as opaque handles.

/// A window handle registered with the bridge. Wraps an NSWindow reference
/// (main-actor-created); the bridge only manipulates it through AppKit calls
/// on the main actor.
public struct RegisteredNoteWindow: Sendable {
    public let noteId: UUID
    /// Opaque token identifying the window registration.
    public let token: UUID
    /// Weak reference to the window (AppKit objects are not Sendable; the
    /// reference is only ever touched on the main actor).
    public let windowRef: WeakWindowRef

    public init(noteId: UUID, token: UUID, windowRef: WeakWindowRef) {
        self.noteId = noteId
        self.token = token
        self.windowRef = windowRef
    }
}

/// A weak, Sendable-safe box for an `NSWindow` reference. Access the window
/// only on the main actor (`MainActor.assumeIsolated` at call sites that
/// already hop there).
public final class WeakWindowRef: @unchecked Sendable {
    private weak var _window: NSWindow?
    public init(_ window: NSWindow?) {
        _window = window
    }

    @MainActor
    public func window() -> NSWindow? { _window }
}

/// The note-window bridge: registration, focus, level, and collection
/// behavior. AppKit-isolated (plan §Module boundaries).
public enum NoteWindowBridge {

    /// FR-035 (T146): note windows must not appear on every Space and must
    /// not force themselves over full-screen applications. `.moveToActiveSpace`
    /// moves the window when the user focuses it; `participatesInCycle` keeps
    /// ⌘` cycling natural. `.fullScreenAuxiliary` is NOT set.
    public static func collectionBehavior(alwaysOnTop: Bool) -> NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [.moveToActiveSpace, .participatesInCycle]
        if alwaysOnTop {
            behavior.insert(.fullScreenAuxiliary)
        }
        return behavior
    }

    /// Applies the FR-035 collection behavior to a window on the main actor.
    @MainActor
    public static func applyCollectionBehavior(_ window: NSWindow, alwaysOnTop: Bool) {
        window.collectionBehavior = collectionBehavior(alwaysOnTop: alwaysOnTop)
    }

    /// Registers a window for a note. Replaces any prior registration for
    /// the same note (one window per note — FR-005).
    @MainActor
    public static func register(_ window: NSWindow, noteId: UUID) -> RegisteredNoteWindow {
        let token = UUID()
        let registration = RegisteredNoteWindow(
            noteId: noteId,
            token: token,
            windowRef: WeakWindowRef(window)
        )
        registry.withLock { $0[noteId] = registration }
        return registration
    }

    /// Unregisters a note's window (idempotent).
    @MainActor
    public static func unregister(noteId: UUID) {
        registry.withLock { $0[noteId] = nil }
    }

    /// The registered window for a note, if any.
    @MainActor
    public static func registeredWindow(for noteId: UUID) -> NSWindow? {
        registry.withLock { $0[noteId] }?.windowRef.window()
    }

    /// `true` when a note already has a registered window.
    public static func isOpen(noteId: UUID) -> Bool {
        registry.withLock { $0[noteId] != nil }
    }

    /// All current registrations (for display-change frame re-application,
    /// T289). The window refs are only touched on the main actor.
    @MainActor
    public static func allRegistrations() -> [UUID: RegisteredNoteWindow] {
        registry.withLock { $0 }
    }

    /// Focuses the note's existing window if registered (FR-005: focus
    /// existing, never duplicate). Returns `false` when no window is open.
    @MainActor
    @discardableResult
    public static func focusExisting(noteId: UUID) -> Bool {
        guard let window = registeredWindow(for: noteId) else { return false }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        return true
    }

    /// One-window-per-note coordination: registers the new window and
    /// returns `true` when it should become key (no existing window). The
    /// caller closes any pre-existing window (FR-005).
    @MainActor
    public static func registerOpeningWindow(_ window: NSWindow, noteId: UUID) -> Bool {
        let existing = registeredWindow(for: noteId)
        if let existing, existing !== window {
            existing.close()
        }
        _ = register(window, noteId: noteId)
        return existing == nil
    }

    private static let registry = OSAllocatedUnfairLock(initialState: [UUID: RegisteredNoteWindow]())
}

// MARK: - Window space behavior (T151, FR-035)

/// Pure decision core for the FR-035 space/full-screen behavior — testable
/// without AppKit windows (T151 WindowSpaceBehaviorTests).
public enum WindowSpaceBehavior {
    /// Whether the given collection behavior keeps the window out of every
    /// Space (i.e. it does NOT use `.canJoinAllSpaces`).
    public static func doesNotJoinAllSpaces(_ behavior: NSWindow.CollectionBehavior) -> Bool {
        !behavior.contains(.canJoinAllSpaces)
    }

    /// Whether the given collection behavior avoids forcing over full-screen
    /// applications (i.e. it is NOT a plain `.fullScreenAuxiliary`-only
    /// window; auxiliary windows sit above full-screen apps).
    public static func doesNotForceOverFullScreen(_ behavior: NSWindow.CollectionBehavior) -> Bool {
        !behavior.contains(.fullScreenAuxiliary)
    }

    /// Whether an always-on-top window may float above full-screen apps
    /// (the app's documented exception to "not forcing over full-screen":
    /// per-note Always-on-Top is a user choice — FR-036).
    public static func floatsAboveFullScreen(alwaysOnTop: Bool) -> Bool {
        alwaysOnTop
    }
}
