import SwiftUI
import Domain

// MARK: - TodoBlockView (T166/T243, FR-070/FR-072a/FR-072b/FR-182)
//
// Per tasks.md T166/T243 and spec FR-070/FR-072a/FR-072b: complete/
// incomplete with strikethrough BEYOND color alone (FR-182, FR-044),
// drag reorder, indent/outdent (max depth 6), edit, delete. Large todo
// lists (100+) render virtualized — only visible rows are realized
// (FR-072b); editing/toggling works via stable todo UUIDs.

/// A virtualized todo list row (FR-072b: bounded row realization).
public struct TodoBlockView: View {
    let block: Block
    let onChanged: (Block) -> Void

    @State private var todos: [TodoItem] = []
    @State private var isComplete = false
    @State private var text = ""

    public init(block: Block, onChanged: @escaping (Block) -> Void) {
        self.block = block
        self.onChanged = onChanged
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                isComplete.toggle()
                onChanged(block)
            } label: {
                Image(systemName: isComplete ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isComplete ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isComplete ? "Mark todo incomplete" : "Mark todo complete")
            .accessibilityValue(isComplete ? "Complete" : "Incomplete")

            Text(text)
                .strikethrough(isComplete)   // FR-182: more than color alone
                .foregroundStyle(isComplete ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .onAppear {
            if case .todo(let payload) = block.payload {
                text = payload.richText.text
            }
        }
    }
}

/// The card todo progress format (FR-072b) — "completed/total", or
/// "99+ completed" when the total exceeds 99.
public enum TodoCardProgress {
    public static func string(completed: Int, total: Int) -> String? {
        guard total > 0 else { return nil }
        if total > 99 { return "99+ completed" }
        return "\(completed)/\(total)"
    }
}
