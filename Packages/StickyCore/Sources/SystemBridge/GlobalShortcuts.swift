import Foundation
import Carbon
import Domain
import os

// MARK: - GlobalShortcuts (T102)
//
// Per tasks.md T102 and plan §Global shortcuts:
//
// - Thin native adapter over Carbon `RegisterEventHotKey` /
//   `UnregisterEventHotKey` — the long-standing macOS API for global
//   hotkeys that does NOT require Accessibility permission (research.md R5,
//   validated in Milestone 0 by GlobalShortcutPrototype).
// - Detects registration failure (kEventHotKeyExists = -9878 and friends)
//   and surfaces a clear error.
// - Can unregister/re-register; supports user configuration.
// - Conflict detection is best-effort (the system does not always expose
//   existing bindings) — registration failure is reported, not swallowed.
// - No global event tap for ordinary shortcuts (constitution VI).
//
// Shortcut definitions are stored as plain key codes + Carbon modifiers —
// language-neutral (plan §Localization: no localized strings as protocol
// identifiers).

/// A user-configurable shortcut: a Carbon key code + Carbon modifier flags.
public struct GlobalShortcutKey: Hashable, Sendable, Equatable {
    /// Carbon virtual key code (kVK_* constants).
    public let keyCode: UInt32
    /// Carbon modifier flags (cmdKey | shiftKey | optionKey | controlKey).
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Command+Option+Shift+N (default "new note from clipboard" — FR-120).
    public static let defaultClipboardNote = GlobalShortcutKey(
        keyCode: 45, // kVK_ANSI_N
        modifiers: UInt32(cmdKey | optionKey | shiftKey)
    )
}

/// Shortcut registration outcomes. Sanitized codes only (constitution VI).
public enum GlobalShortcutError: Error, Sendable, Equatable {
    case registrationFailed
    case duplicateRegistration
    case unregistrationFailed
    case eventLoopUnavailable

    public var sanitizedCode: String {
        switch self {
        case .registrationFailed: return "shortcut.registrationFailed"
        case .duplicateRegistration: return "shortcut.duplicateRegistration"
        case .unregistrationFailed: return "shortcut.unregistrationFailed"
        case .eventLoopUnavailable: return "shortcut.eventLoopUnavailable"
        }
    }
}

/// Callback invoked (on the main actor) when a registered shortcut fires.
public typealias GlobalShortcutHandler = @MainActor @Sendable (GlobalShortcutKey) -> Void

// MARK: - Carbon plumbing (top-level C callback + concurrency-safe registry)

private let shortcutsSignature: FourCharCode = 0x53544E4B // 'STNK'

/// Registry guarded for concurrent access from the C event callback.
/// Maps (signature-scoped) hotkey ID → the key + handler.
private let shortcutRegistry = OSAllocatedUnfairLock(initialState: [UInt32: RegisteredShortcut]())

private struct RegisteredShortcut: Sendable {
    let key: GlobalShortcutKey
    let handler: GlobalShortcutHandler
}

/// The Carbon event handler. Top-level C function (required for the C
/// function pointer). Safe under strict concurrency: it only touches the
/// lock-guarded registry.
private func shortcutEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == shortcutsSignature else {
        return noErr
    }
    let hotKeyIDValue = hotKeyID.id
    let registered = shortcutRegistry.withLock { $0[hotKeyIDValue] }
    if let registered {
        // Hop to the main actor: handlers are UI-facing.
        Task { @MainActor in
            registered.handler(registered.key)
        }
    }
    return noErr
}

/// The global-shortcut adapter. One instance owns the event handler and the
/// registry of active shortcuts.
public final class GlobalShortcuts: @unchecked Sendable {
    /// Lock-guarded Carbon handler ref (installed once).
    private static let handlerRefLock = OSAllocatedUnfairLock(initialState: CarbonHandlerRef?.none)

    /// Installs the Carbon event handler exactly once (idempotent + race
    /// free). Called automatically by `register`.
    private static func ensureEventHandlerInstalled() throws {
        if handlerRefLock.withLock({ $0 != nil }) { return }
        // Install while holding the lock: parallel callers would otherwise
        // both attempt InstallEventHandler.
        try handlerRefLock.withLock { state in
            if state != nil { return }
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            var ref: EventHandlerRef?
            let status = InstallEventHandler(
                GetEventDispatcherTarget(),
                shortcutEventHandler,
                1,
                &eventType,
                nil,
                &ref
            )
            guard status == noErr, let ref else {
                throw GlobalShortcutError.registrationFailed
            }
            state = CarbonHandlerRef(ref: ref)
        }
    }

    /// Registers a shortcut. Throws `.duplicateRegistration` when the key
    /// is already bound (either by us or by another app).
    @discardableResult
    public static func register(
        _ key: GlobalShortcutKey,
        handler: @escaping GlobalShortcutHandler
    ) throws -> GlobalShortcutRegistration {
        try ensureEventHandlerInstalled()

        // Unique ID per key so the handler can look up the right action.
        let id: UInt32 = key.keyCode &* 31 &+ key.modifiers &* 17
        let hotKeyID = EventHotKeyID(signature: shortcutsSignature, id: id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            key.keyCode,
            key.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            throw GlobalShortcutError.duplicateRegistration
        }

        shortcutRegistry.withLock {
            $0[id] = RegisteredShortcut(key: key, handler: handler)
        }
        return GlobalShortcutRegistration(key: key, hotKeyID: id, hotKeyRef: hotKeyRef)
    }

    /// Unregisters a shortcut previously returned by `register`.
    public static func unregister(_ registration: GlobalShortcutRegistration) throws {
        let status = UnregisterEventHotKey(registration.rawHotKeyRef)
        guard status == noErr else {
            throw GlobalShortcutError.unregistrationFailed
        }
        shortcutRegistry.withLock { $0[registration.hotKeyID] = nil }
    }

    /// Re-registers a shortcut (unregister + register round-trip). Useful
    /// after a settings change or registration loss.
    public static func reRegister(
        _ registration: GlobalShortcutRegistration,
        with key: GlobalShortcutKey,
        handler: @escaping GlobalShortcutHandler
    ) throws -> GlobalShortcutRegistration {
        try unregister(registration)
        return try register(key, handler: handler)
    }
}

/// An active shortcut registration (opaque handle). Carbon pointers are
/// non-Sendable; the raw ref is boxed in an `@unchecked Sendable` wrapper
/// (ownership stays with Carbon — this is a passive handle).
public struct GlobalShortcutRegistration: Sendable {
    public let key: GlobalShortcutKey
    /// The Carbon hotkey ID (the registry key).
    public let hotKeyID: UInt32
    /// The Carbon hotkey ref (boxed; Carbon owns the object).
    fileprivate let hotKeyRef: CarbonHotKeyRef

    fileprivate init(key: GlobalShortcutKey, hotKeyID: UInt32, hotKeyRef: EventHotKeyRef) {
        self.key = key
        self.hotKeyID = hotKeyID
        self.hotKeyRef = CarbonHotKeyRef(ref: hotKeyRef)
    }

    var rawHotKeyRef: EventHotKeyRef {
        hotKeyRef.ref
    }
}

/// Passive box for a Carbon `EventHotKeyRef` (opaque pointer). `@unchecked
/// Sendable` is justified: the value is an opaque handle whose lifetime is
/// managed by Carbon, and it is only ever used to unregister.
private struct CarbonHotKeyRef: @unchecked Sendable {
    let ref: EventHotKeyRef
}

/// Passive box for the Carbon event-handler ref.
private struct CarbonHandlerRef: @unchecked Sendable {
    let ref: EventHandlerRef
}
