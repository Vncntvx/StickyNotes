// swift-tools-version: 6.2
//
// Milestone 0 prototypes (tasks.md T025a / T155) — hard risk gate.
//
// Scratch package OUTSIDE StickyCore: no library/test-target changes are
// made to the main package by anything here. Each executable validates one
// high-risk assumption from research.md R0–R18:
//
//   MarkdownUndoPrototype     R1  — Markdown conversion with single-Undo (CLI, headless)
//   AppGroupGRDBPrototype     R6  — App Group GRDB WAL multi-process access (CLI, headless)
//   GlobalShortcutPrototype   R5  — Carbon RegisterEventHotKey, no Accessibility (CLI)
//   Argon2idPrototype         R9  — Argon2id KEK derivation + RFC 9106 vectors (CLI, headless)
//   RichTextIMEPrototype      R1  — SwiftUI TextEditor + AttributedString + Chinese IME (GUI)
//   WindowCoordinatorPrototype R3/R4 — one-window-per-note + per-window floating (GUI)
//   ScreenCapturePrototype    R7  — ScreenCaptureKit single frame + region overlay (GUI)
//
// See README.md for the gate report and how to run each prototype.

import PackageDescription

let package = Package(
    name: "Prototypes",
    platforms: [
        .macOS(.v26),
    ],
    dependencies: [
        // Local main package — read-only dependency for prototypes that
        // validate already-implemented production code (EditorCore, Persistence).
        .package(path: "../Packages/StickyCore"),
        // R9 selection record: SwiftArgon2 v1.0.4 (MIT, pure Swift 6, zero
        // transitive deps, RFC 9106 compliant, Sendable). Criteria in
        // research.md §R9 — finalized by Argon2idPrototype.
        .package(url: "https://github.com/mimiclone/argon2-swift.git", from: "1.0.4"),
    ],
    targets: [
        // MARK: - Headless CLI prototypes (verifiable in CI / CLT-only machines)

        .executableTarget(
            name: "MarkdownUndoPrototype",
            dependencies: [
                .product(name: "EditorCore", package: "StickyCore"),
                .product(name: "Domain", package: "StickyCore"),
            ],
            path: "Sources/MarkdownUndoPrototype"
        ),
        .executableTarget(
            name: "AppGroupGRDBPrototype",
            dependencies: [
                .product(name: "Persistence", package: "StickyCore"),
            ],
            path: "Sources/AppGroupGRDBPrototype"
        ),
        .executableTarget(
            name: "GlobalShortcutPrototype",
            path: "Sources/GlobalShortcutPrototype"
        ),
        .executableTarget(
            name: "Argon2idPrototype",
            dependencies: [
                .product(name: "SwiftArgon2", package: "argon2-swift"),
            ],
            path: "Sources/Argon2idPrototype"
        ),

        // MARK: - GUI prototypes (compile-verified; interactive run needed)

        .executableTarget(
            name: "RichTextIMEPrototype",
            dependencies: [
                .product(name: "Domain", package: "StickyCore"),
            ],
            path: "Sources/RichTextIMEPrototype"
        ),
        .executableTarget(
            name: "WindowCoordinatorPrototype",
            path: "Sources/WindowCoordinatorPrototype"
        ),
        .executableTarget(
            name: "ScreenCapturePrototype",
            path: "Sources/ScreenCapturePrototype"
        ),
    ]
)
