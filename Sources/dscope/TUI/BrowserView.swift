import DiskKit
import Foundation

/// Renders the browser as a full frame of terminal lines.
enum BrowserView {

    static func render(_ state: BrowserState, size: (rows: Int, columns: Int)) -> [String] {
        let width = size.columns
        var lines: [String] = []

        lines.append(header(state, width: width))
        lines.append(Style.dim(String(repeating: "─", count: width)))

        let bodyHeight = max(1, size.rows - 4)
        lines.append(contentsOf: body(state, width: width, height: bodyHeight))

        lines.append(Style.dim(String(repeating: "─", count: width)))
        lines.append(footer(state, width: width))
        return lines
    }

    // MARK: - Sections

    private static func header(_ state: BrowserState, width: Int) -> String {
        if let search = state.search {
            // The whole field is highlighted, not just its label: the typed
            // text is what needs to stand out, and as plain text it looks no
            // different from the list underneath.
            let label = search.mode == .regex ? "regex" : "search"
            let typed = truncate(search.query, to: max(8, width - 46))
            let caret = search.isEditing ? "█" : " "

            let hint: String
            if let error = search.error {
                hint = error
            } else if search.query.isEmpty {
                hint = "esc cancels"
            } else {
                hint = "\(state.rows.count) matches · enter keeps them · esc cancels"
            }

            // A fixed-width field, so it reads as a box to type into whether or
            // not anything has been typed yet.
            let fieldWidth = max(20, width - hint.count - label.count - 6)
            let contents = " \(typed)\(caret)".rightPadded(to: fieldWidth)

            return Style.bold("\(label) ") + Style.inverted(contents) + Style.dim("  \(hint)")
        }

        let path = truncate(state.current.path, to: width - 32)
        let size = state.current.size.formattedBytes()

        // Position in the list, so a long directory does not leave you guessing
        // where you are or how much is below.
        let total = state.displayCount
        let position = total == 0 ? "" : "  \(state.cursor + 1)/\(total)"
        return Style.bold(path) + Style.dim("  \(size)\(position)")
    }

    private static func body(_ state: BrowserState, width: Int, height: Int) -> [String] {
        guard !state.rows.isEmpty else {
            // With nothing typed yet there is no search to have failed.
            let message: String
            if let search = state.search, search.query.isEmpty {
                message = "searching \(state.snapshot.rootPath) and everything under it"
            } else {
                message = state.isSearching ? "no matches" : "empty"
            }
            return [Style.dim("  " + message)] + Array(repeating: "", count: height - 1)
        }

        let scroll = visibleWindow(state: state, height: height)
        var lines: [String] = []

        for index in scroll ..< min(state.displayCount, scroll + height) {
            if let fold = state.foldedRow, index == fold.index {
                lines.append(foldRow(fold, isCursor: index == state.cursor, width: width))
                continue
            }
            guard let rowIndex = state.rowIndex(forCursor: index), rowIndex < state.rows.count
            else { continue }
            lines.append(row(state.rows[rowIndex], state: state, isCursor: index == state.cursor, width: width))
        }
        while lines.count < height { lines.append("") }
        return lines
    }

    private static func row(_ node: Node, state: BrowserState, isCursor: Bool, width: Int) -> String {
        let marker = state.selection.covers(node) ? "✓" : " "
        let size = node.size.formattedBytes().leftPadded(to: 9)
        let share = bar(node.shareOfParent)

        // Under search the name alone is ambiguous; show where it lives.
        let label: String
        if state.isSearching {
            label = node.path
        } else {
            label = node.name + (node.isDirectory ? "/" : "")
        }

        // An arrow as well as the inverted row: reverse video is easy to lose
        // against some terminal themes, and the cursor is the one thing that
        // must always be findable.
        let pointer = isCursor ? "▸" : " "
        let prefix = "\(pointer)\(marker) \(size) \(share) "
        let name = truncate(label, to: max(4, width - prefix.count - 1))
        let line = prefix + name

        if isCursor {
            return Style.inverted(line.rightPadded(to: width))
        }
        if node.error != nil {
            return Style.dim(line)
        }
        return node.isDirectory ? line : Style.dim(line)
    }

    /// The folded row, drawn as the directory it behaves like.
    private static func foldRow(
        _ fold: BrowserState.FoldedRow,
        isCursor: Bool,
        width: Int
    ) -> String {
        let pointer = isCursor ? "▸" : " "
        let size = fold.bytes.formattedBytes().leftPadded(to: 9)
        let label = "\(fold.nodes.count) smaller entries/"
        let line = "\(pointer)  \(size) \(bar(0)) \(label)"

        return isCursor
            ? Style.inverted(line.rightPadded(to: width))
            : Style.dim(line)
    }

    /// A short bar giving the share of the parent at a glance.
    private static func bar(_ share: Double) -> String {
        let width = 8
        let filled = Int((share * Double(width)).rounded())
        let clamped = max(0, min(width, filled))
        return Style.dim(String(repeating: "█", count: clamped) + String(repeating: "·", count: width - clamped))
    }

    private static func footer(_ state: BrowserState, width: Int) -> String {
        if let status = state.status {
            return Style.dim(truncate(status, to: width))
        }
        if state.search?.isEditing == true {
            return Style.dim("enter: keep results   esc: cancel")
        }

        // Built from plain text and truncated before styling: escape codes take
        // no columns, and counting them would trim the visible text too early.
        var plain: [String] = []
        if !state.selection.isEmpty {
            plain.append("\(state.selection.count) selected, \(state.selectionSize.formattedBytes())")
        }
        plain.append("↑↓ move  → enter  ← up  space mark  a all  / search  s sort:\(state.order.rawValue)")
        plain.append("d trash  q quit")

        let line = plain.joined(separator: "  ·  ")
        guard line.count > width else {
            return state.selection.isEmpty ? Style.dim(line) : Style.bold(plain[0]) + Style.dim(String(line.dropFirst(plain[0].count)))
        }
        // Keep the head, which carries the selection total, and drop the hints.
        return Style.bold(String(line.prefix(width)))
    }

    // MARK: - Layout

    /// Scroll offset keeping the cursor on screen with a little context.
    private static func visibleWindow(state: BrowserState, height: Int) -> Int {
        let total = state.displayCount
        let limit = max(0, total - height)
        var scroll = min(state.scroll, limit)

        // Keep a couple of rows of context around the cursor where there is
        // room, but never at the cost of scrolling it off screen entirely.
        let margin = min(2, max(0, (height - 1) / 2))

        if state.cursor < scroll + margin {
            scroll = state.cursor - margin
        }
        if state.cursor > scroll + height - 1 - margin {
            scroll = state.cursor - height + 1 + margin
        }
        return max(0, min(scroll, limit))
    }

    static func scrollOffset(for state: BrowserState, height: Int) -> Int {
        visibleWindow(state: state, height: height)
    }

    /// Trims from the left, so the tail of a long path stays visible.
    private static func truncate(_ text: String, to width: Int) -> String {
        guard width > 1, text.count > width else { return text }
        return "…" + String(text.suffix(width - 1))
    }
}

enum Style {
    static func bold(_ text: String) -> String { "\u{1B}[1m\(text)\u{1B}[0m" }
    static func dim(_ text: String) -> String { "\u{1B}[2m\(text)\u{1B}[0m" }
    static func inverted(_ text: String) -> String { "\u{1B}[7m\(text)\u{1B}[0m" }

    /// Escape codes occupy no columns; this accounts for them when padding.
    static func overhead(_ count: Int) -> Int { count * 8 }
}

extension String {

    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }

    func rightPadded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
