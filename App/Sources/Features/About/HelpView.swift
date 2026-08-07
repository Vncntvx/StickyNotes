import SwiftUI

// MARK: - HelpView (T288, FR-004/FR-008/FR-052a)
//
// Per tasks.md T288 and spec FR-004/FR-008: a Help surface reachable from
// the menu-bar library so Settings/Help/About/sync status/Quit all remain
// reachable when the Dock icon is disabled (accessory activation policy).
// Documents keyboard shortcuts (FR-052a: "keyboard shortcuts (documented in
// Help)"), the auto-save model, and the menu-bar-primary model (FR-014a).
// All strings resolve from the localization catalogs (FR-180a).

/// The localized Help panel.
public struct HelpView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sticky Notes Help")
                    .font(.title2.bold())

                HelpSection(
                    title: String(localized: "Menu-bar first"),
                    text: String(localized: "Sticky Notes lives in the menu bar. Click the note icon to open your library; click it again to dismiss. The library is your home for creating, searching, and organizing notes.")
                )

                HelpSection(
                    title: String(localized: "Auto-save"),
                    text: String(localized: "Notes save automatically as you type — there is no Save button. Close a note window and reopen it later; your content is preserved. A note you never wrote anything into is removed automatically when its window closes.")
                )

                HelpSection(
                    title: String(localized: "Keyboard shortcuts"),
                    text: String(localized: "⌘N — new note\n⌘W — close note window\n⌘Q — quit Sticky Notes\n⌘F — search your notes")
                )

                HelpSection(
                    title: String(localized: "Markdown shortcuts"),
                    text: String(localized: "Type “# ” for a heading, “- ” for a bullet, “- [ ] ” for a todo, “**text**” for bold, “*text*” for italic, and three backticks for a code block. A single Undo (⌘Z) restores the exact Markdown you typed.")
                )

                HelpSection(
                    title: String(localized: "Search"),
                    text: String(localized: "Search matches titles, note text, todo items, code blocks, file names, and screenshot captions. Use the sort menu to switch between Recently Modified, Created, Title, and Manual order.")
                )

                HelpSection(
                    title: String(localized: "Screenshots and files"),
                    text: String(localized: "Add a screenshot or a file reference from a note's upper control area. Files are referenced, never copied. A screenshot viewer opens in its own window with zoom and caption editing.")
                )

                HelpSection(
                    title: String(localized: "Synchronization"),
                    text: String(localized: "Synchronization is optional and end-to-end encrypted. Configure exactly one WebDAV or S3-compatible repository in Settings. Your notes are encrypted on this Mac before upload; forgetting your sync password makes encrypted remote data unrecoverable.")
                )
            }
            .padding(20)
            .frame(maxWidth: 480, alignment: .leading)
        }
        .frame(width: 520, height: 560)
    }
}

/// A labeled help paragraph.
private struct HelpSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
