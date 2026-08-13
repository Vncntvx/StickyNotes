import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Domain
import SystemBridge

// MARK: - CodeBlockView (T166, FR-080/FR-081)
//
// Per tasks.md T166 and spec FR-080/FR-081: monospaced, whitespace
// preserved (tabs/line breaks exact), copy button copying ONLY the code,
// optional language label, wrap-or-scroll.
//
// 004 修复 (2026-08-13): the code block is EDITABLE — a plain-text
// monospaced editor (CodeTextView) committing into `CodePayload.text`,
// inside the same unified editing context (shared UndoManager, selection
// bridge focus → `.afterBlock` insertion targeting, insertion-focus
// request). ⌘B/⌘I are a no-op here by contract (plain text).

public struct CodeBlockView: View {
    let block: Block
    let onChanged: (Block) -> Void
    /// 004 修复: unified editing context wiring.
    let selectionBridge: EditorSelectionBridge?
    let undoManager: UndoManager?
    let requestFocus: Bool
    let onFocusRequestHandled: () -> Void

    public init(
        block: Block,
        onChanged: @escaping (Block) -> Void = { _ in },
        selectionBridge: EditorSelectionBridge? = nil,
        undoManager: UndoManager? = nil,
        requestFocus: Bool = false,
        onFocusRequestHandled: @escaping () -> Void = {}
    ) {
        self.block = block
        self.onChanged = onChanged
        self.selectionBridge = selectionBridge
        self.undoManager = undoManager
        self.requestFocus = requestFocus
        self.onFocusRequestHandled = onFocusRequestHandled
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let language = payloadLanguage, !language.isEmpty {
                Text(language)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 8) {
                CodeTextView(
                    text: payloadText,
                    onCommit: { newText in
                        commitCode(newText)
                    },
                    selectionBridge: selectionBridge,
                    blockId: block.id,
                    undoManager: undoManager,
                    requestFocus: requestFocus,
                    onFocusRequestHandled: onFocusRequestHandled
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    copyCode()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy code")
                .accessibilityLabel("Copy code")
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private var payloadText: String {
        if case .code(let payload) = block.payload { return payload.text }
        return ""
    }

    private var payloadLanguage: String? {
        if case .code(let payload) = block.payload { return payload.language }
        return nil
    }

    /// Commits an edit into `CodePayload.text` (language preserved).
    private func commitCode(_ text: String) {
        guard case .code(let payload) = block.payload else { return }
        let updated = Block(
            id: block.id,
            noteId: block.noteId,
            kind: block.kind,
            sortKey: block.sortKey,
            payload: .code(CodePayload(text: text, language: payload.language)),
            versionId: block.versionId,
            parentVersionId: block.parentVersionId,
            lastModifiedDeviceId: DeviceIdentity.current.id,
            createdAt: block.createdAt,
            modifiedAt: Date()
        )
        onChanged(updated)
    }

    /// FR-081: copy copies ONLY the code text.
    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payloadText, forType: .string)
    }
}

// MARK: - FileReferenceCardView (T166/T271/T279/T291, FR-100/FR-101/FR-102/FR-103/FR-104/FR-105)

/// The file-reference card actions (T291) — resolved by the host through
/// SecurityScopedBookmarks / FileDragOutBridge / the repositories.
public enum FileReferenceAction: Sendable {
    case open
    case reveal
    case copyPath
    case relink
    case remove
    case move  // explicit move: the host presents the destination picker
}

/// The file-reference card: name/icon/size/date/availability/origin device
/// + open/reveal/copy-path/drag-out/move/relink/remove. The availability
/// indicator distinguishes the four FR-100 states by MORE than color alone
/// (icon + text, FR-044). Availability is evaluated from the device-local
/// FileLocator bookmark (FR-105) — the pre-Phase-27 version hardcoded
/// `.available`.
public struct FileReferenceCardView: View {
    let block: Block
    let onAction: (FileReferenceAction) -> Void
    /// Evaluates the FR-100 availability from the device-local locator
    /// (bookmark resolution — FR-105). Loaded on appear (T291).
    let availabilityProvider: (UUID) async -> FileAvailability

    @State private var displayName = ""
    @State private var contentType = ""
    @State private var approximateSize: Int?
    @State private var availability: FileAvailability = .onAnotherDevice

    public init(
        block: Block,
        onAction: @escaping (FileReferenceAction) -> Void = { _ in },
        availabilityProvider: @escaping (UUID) async -> FileAvailability = { _ in .onAnotherDevice }
    ) {
        self.block = block
        self.onAction = onAction
        self.availabilityProvider = availabilityProvider
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.callout)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let size = approximateSize {
                        Text(DisplayFormatters.fileSize(size))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    // FR-100: state communicated by icon + text (FR-044).
                    availabilityIndicator
                }
            }

            Spacer()

            Button {
                onAction(.open)
            } label: {
                Image(systemName: "arrow.up.doc")
            }
            .buttonStyle(.plain)
            .help("Open file")
            .accessibilityLabel("Open file")
            .disabled(availability == .missing || availability == .onAnotherDevice)

            Menu {
                Button("Reveal in Finder") { onAction(.reveal) }
                Button("Copy Path") { onAction(.copyPath) }
                Button("Relink…") { onAction(.relink) }
                Button("Move File…") { onAction(.move) }
                Divider()
                Button("Remove Reference", role: .destructive) { onAction(.remove) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.plain)
            .help("File actions")
            .accessibilityLabel("More file actions")
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        .task {
            if case .fileReference(let ref) = block.payload {
                displayName = ref.displayName
                contentType = ref.contentType
                approximateSize = ref.approximateSize
            }
            // FR-100: availability evaluated from the device-local locator
            // by the host (bookmark resolution — FR-105).
            availability = await availabilityProvider(block.id)
        }
        .onChange(of: block.id) { _, _ in
            if case .fileReference(let ref) = block.payload {
                displayName = ref.displayName
                contentType = ref.contentType
                approximateSize = ref.approximateSize
            }
        }
    }

    @ViewBuilder
    private var availabilityIndicator: some View {
        switch availability {
        case .available:
            Label("Available", systemImage: "checkmark.circle")
                .labelStyle(.titleAndIcon)
        case .missing:
            Label("Missing — relink to open", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .stale:
            Label("File may have moved", systemImage: "questionmark.circle")
                .foregroundStyle(.yellow)
        case .relinked:
            Label("Relinked", systemImage: "arrow.triangle.2.circlepath")
        case .onAnotherDevice:
            Label("On another device", systemImage: "icloud")
                .foregroundStyle(.secondary)
        }
    }

    private var iconName: String {
        if let type = UTType(contentType) {
            return type == .image ? "photo" : "doc"
        }
        return "doc"
    }
}
