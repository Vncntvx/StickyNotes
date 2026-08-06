// swift-tools-version: 6.2
//
// StickyCore — local Swift package for the macOS Sticky Notes app.
//
// Eight SwiftPM targets map 1:1 to the constitution's required separable
// concerns and enforce the dependency direction from plan.md
// §Module boundaries at the compiler level. The App and WidgetExtension
// targets depend on this package; the Widget target imports only the
// minimal Domain + Persistence surface and never links SyncCore/SecurityCore.
//
// Toolchain baseline (research.md R0): macOS 26 deployment target, Swift 6.3
// in Swift 6 language mode with strict concurrency. The dev machine runs
// Xcode-beta (Swift 6.4, macOS 27 SDK); the macOS 26 minimum is preserved
// here regardless — see AGENTS.md §Environment gotchas.

import PackageDescription

let package = Package(
    name: "StickyCore",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "EditorCore", targets: ["EditorCore"]),
        .library(name: "AssetStore", targets: ["AssetStore"]),
        .library(name: "SecurityCore", targets: ["SecurityCore"]),
        .library(name: "SyncCore", targets: ["SyncCore"]),
        .library(name: "SystemBridge", targets: ["SystemBridge"]),
    ],
    dependencies: [
        // GRDB.swift — the only approved third-party dependency for SQLite
        // (migrations, WAL, FTS5). Pinned via Package.resolved. Wired into
        // the Persistence target only (constitution XIII; plan §Dependencies).
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.0"),
        // SwiftArgon2 v1.0.4 — the R9-selected Argon2id implementation
        // (MIT, pure Swift 6, zero transitive deps, RFC 9106 compliant).
        // Selection record: Prototypes/README.md §R9. Wired into the
        // SecurityCore target only (constitution VII + XIII).
        .package(url: "https://github.com/mimiclone/argon2-swift.git", from: "1.0.4"),
    ],
    targets: [
        // MARK: - Library targets

        // Domain: Foundation-only models & rules. No SwiftUI/AppKit/GRDB/
        // URLSession/Keychain/provider types.
        .target(
            name: "Domain",
            path: "Sources/Domain"
        ),

        // EditorCore: block ops, Markdown FSM, canonical conversion.
        // Depends on Domain only.
        .target(
            name: "EditorCore",
            dependencies: ["Domain"],
            path: "Sources/EditorCore"
        ),

        // Persistence: GRDB, migrations, FTS5, repositories. Depends on
        // Domain + GRDB. Exposes repository protocols; concrete DB rows are
        // NOT exported as contracts.
        .target(
            name: "Persistence",
            dependencies: [
                "Domain",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/Persistence"
        ),

        // AssetStore: atomic asset writes, thumbnails, hashing. Depends on
        // Domain + Apple image/file frameworks.
        .target(
            name: "AssetStore",
            dependencies: ["Domain"],
            path: "Sources/AssetStore"
        ),

        // SecurityCore: vault, KDF, key wrap, AES-GCM envelopes. Depends on
        // Domain + CryptoKit + Security (Keychain) + SwiftArgon2 (R9).
        .target(
            name: "SecurityCore",
            dependencies: [
                "Domain",
                .product(name: "SwiftArgon2", package: "argon2-swift"),
            ],
            path: "Sources/SecurityCore"
        ),

        // SyncCore: provider protocol, WebDAV, S3-SigV4, sync engine.
        // Depends on Domain + SecurityCore + Persistence + AssetStore (the
        // engine delegates asset byte I/O to AssetStore while owning asset
        // metadata via raw SQL, mirroring how it owns note/tombstone rows).
        .target(
            name: "SyncCore",
            dependencies: [
                "Domain",
                "SecurityCore",
                "Persistence",
                "AssetStore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/SyncCore"
        ),

        // SystemBridge: NSWindow/Dock/shortcuts/bookmarks/permissions.
        // AppKit/Carbon/ScreenCaptureKit/Security isolated here.
        .target(
            name: "SystemBridge",
            dependencies: ["Domain"],
            path: "Sources/SystemBridge"
        ),

        // MARK: - Test targets
        // Tests are MANDATORY (constitution XII). Each test target depends
        // only on the module it tests (plus transitive Domain where needed).

        .testTarget(
            name: "DomainTests",
            dependencies: ["Domain"],
            path: "Tests/DomainTests"
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "Domain"],
            path: "Tests/PersistenceTests",
            resources: [
                // Migration fixture databases — one per historical schema
                // version. NEVER contains real note content (constitution VI).
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "EditorCoreTests",
            dependencies: ["EditorCore", "Domain"],
            path: "Tests/EditorCoreTests"
        ),
        .testTarget(
            name: "AssetStoreTests",
            dependencies: ["AssetStore", "Domain"],
            path: "Tests/AssetStoreTests"
        ),
        .testTarget(
            name: "SecurityCoreTests",
            dependencies: ["SecurityCore", "Domain"],
            path: "Tests/SecurityCoreTests"
        ),
        .testTarget(
            name: "SyncCoreTests",
            dependencies: ["SyncCore", "Domain", "Persistence", "SecurityCore", "AssetStore"],
            path: "Tests/SyncCoreTests"
        ),
        .testTarget(
            name: "SystemBridgeTests",
            dependencies: ["SystemBridge", "Domain"],
            path: "Tests/SystemBridgeTests"
        ),
    ]
)

// MARK: - Swift 6 strict concurrency + treat-warnings-as-errors
//
// Applied to all project-owned targets (constitution XIII; plan §Technical
// Context). Package-level swiftSettings propagate to every target above.
//
// Note: in Swift 6 language mode, `StrictConcurrency`, `IsolatedDefaultValues`,
// and `BareSlashRegexLiterals` are already enabled by default, so they are
// not listed here. `warnings-as-errors` enforces the constitution's quality
// bar for project-owned code.

let strictSettings: [SwiftSetting] = [
    .unsafeFlags(["-warnings-as-errors"]),
]

for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + strictSettings
}
