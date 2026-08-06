import Foundation
import Domain
import Persistence
import EditorCore
import AssetStore
import SecurityCore
import SyncCore
import SystemBridge

// MARK: - AppEnvironment (T024)
//
// A small composition root with explicit-initializer DI. No DI framework
// (constitution XIII; plan §State management and concurrency). The
// environment is constructed at app startup with concrete service instances
// and passed down to scenes via SwiftUI `@Environment`.
//
// Services are composed, not globally singletoned. Each service is an actor
// or a value type returning `Sendable` snapshots; the environment itself is
// a `Sendable` value carrying references to the long-lived services.

/// The composed application services. Constructed at app startup; passed to
/// scenes via SwiftUI `@Environment` (or `@State` at the app root).
///
/// Until the foundational services (Phase 2) and the user-story UIs (Phase 3+)
/// land, this is a `placeholder` that lets the app compile and run for
/// foundation bring-up. Real composition lands incrementally per tasks.md.
public struct AppEnvironment: Sendable {
    public let domain: DomainServices
    public let persistence: PersistenceServices
    public let editor: EditorServices
    public let assets: AssetServices
    public let security: SecurityServices
    public let sync: SyncServices
    public let systemBridge: SystemBridgeServices

    public init(
        domain: DomainServices,
        persistence: PersistenceServices,
        editor: EditorServices,
        assets: AssetServices,
        security: SecurityServices,
        sync: SyncServices,
        systemBridge: SystemBridgeServices
    ) {
        self.domain = domain
        self.persistence = persistence
        self.editor = editor
        self.assets = assets
        self.security = security
        self.sync = sync
        self.systemBridge = systemBridge
    }

    /// Placeholder used during foundation bring-up. Real composition
    /// replaces this once the foundational services exist.
    public static let placeholder = AppEnvironment(
        domain: DomainServices.placeholder,
        persistence: PersistenceServices.placeholder,
        editor: EditorServices.placeholder,
        assets: AssetServices.placeholder,
        security: SecurityServices.placeholder,
        sync: SyncServices.placeholder,
        systemBridge: SystemBridgeServices.placeholder
    )
}

// MARK: - Service groupings
//
// Each grouping is a thin Sendable value that carries references to the
// concrete services from the StickyCore modules. Concrete service types
// land per tasks.md Phase 2 (foundational) and per-user-story phases.

public struct DomainServices: Sendable {
    public init() {}
    public static let placeholder = DomainServices()
}

public struct PersistenceServices: Sendable {
    public init() {}
    public static let placeholder = PersistenceServices()
}

public struct EditorServices: Sendable {
    public init() {}
    public static let placeholder = EditorServices()
}

public struct AssetServices: Sendable {
    public init() {}
    public static let placeholder = AssetServices()
}

public struct SecurityServices: Sendable {
    public init() {}
    public static let placeholder = SecurityServices()
}

public struct SyncServices: Sendable {
    public init() {}
    public static let placeholder = SyncServices()
}

public struct SystemBridgeServices: Sendable {
    public init() {}
    public static let placeholder = SystemBridgeServices()
}
