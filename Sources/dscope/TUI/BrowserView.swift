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
            let caret = search.isEditing ? "▌" : ""
            let label = "search (\(search.mode.rawValue)): \(search.query)\(caret)"
            let note = search.error.map { Style.dim("  \($0)") }
                ?? Style.dim("  \(state.rows.count) matches")
            return Style.bold(truncate(label, to: width - 16)) + note
        }

        let path = truncate(state.current.path, to: width - 24)
        let size = state.current.size.formattedBytes()
        return Style.bold(path) + Style.dim("  \(size)  \(state.rows.count) entries")
    }

    private static func body(_ state: BrowserState, width: Int, height: Int) -> [String] {
        guard !state.rows.isEmpty else {
            let message = state.isSearching ? "no matches" : "empty"
            return [Style.dim("  " + message)] + Array(repeating: "", count: height - 1)
        }

        let scroll = visibleWindow(state: state, height: height)
        var lines: [String] = []

        for index in scroll ..< min(state.rows.count, scroll + height) {
            lines.append(row(state.rows[index], state: state, isCursor: index == state.cursor, width: width))
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

        let prefix = "\(marker) \(size) \(share) "
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
        let margin = 2
        var scroll = state.scroll

        if state.cursor < scroll + margin {
            scroll = max(0, state.cursor - margin)
        }
        if state.cursor >= scroll + height - margin {
            scroll = state.cursor - height + margin + 1
        }
        return max(0, min(scroll, max(0, state.rows.count - height)))
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
