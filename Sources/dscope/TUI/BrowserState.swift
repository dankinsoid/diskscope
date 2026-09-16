import DiskKit
import Foundation

/// What the browser is showing and what the user has marked.
struct BrowserState {

    let snapshot: Snapshot

    /// Directory currently open; rows are its children.
    private(set) var current: Node

    private(set) var rows: [Node]
    var cursor: Int
    var scroll: Int

    var selection = Selection()
    var order: NodeOrder = .size

    /// Set while searching; rows become matches from the whole tree.
    private(set) var search: SearchState?

    var status: String?

    struct SearchState {
        var query: String
        var mode: MatchMode
        var isEditing: Bool
        var error: String?
    }

    init(snapshot: Snapshot) {
        self.snapshot = snapshot
        self.current = snapshot.root
        self.rows = snapshot.root.children
        self.cursor = 0
        self.scroll = 0
    }

    var selectedNode: Node? {
        rows.indices.contains(cursor) ? rows[cursor] : nil
    }

    var isSearching: Bool { search != nil }

    // MARK: - Navigation

    mutating func enter() {
        guard let node = selectedNode else { return }

        // Entering a search result goes to where it lives, not into a filtered view.
        if isSearching {
            open(node.isDirectory ? node : (node.parent ?? node))
            search = nil
            return
        }
        guard node.isDirectory, !node.children.isEmpty else { return }
        open(node)
    }

    mutating func goUp() {
        if isSearching {
            search = nil
            reload()
            return
        }
        guard let parent = current.parent else { return }
        let previous = current
        open(parent)
        cursor = rows.firstIndex { $0 === previous } ?? 0
    }

    mutating func open(_ node: Node) {
        current = node
        cursor = 0
        scroll = 0
        reload()
    }

    mutating func move(by delta: Int) {
        guard !rows.isEmpty else { return }
        cursor = Swift.max(0, Swift.min(rows.count - 1, cursor + delta))
    }

    mutating func moveTo(_ index: Int) {
        guard !rows.isEmpty else { return }
        cursor = Swift.max(0, Swift.min(rows.count - 1, index))
    }

    // MARK: - Sorting and selection

    mutating func cycleOrder() {
        let orders = NodeOrder.allCases
        let index = orders.firstIndex(of: order) ?? 0
        order = orders[(index + 1) % orders.count]
        reload()
    }

    mutating func toggleSelection() {
        guard let node = selectedNode else { return }
        selection.toggle(node)
    }

    /// Marks every row currently listed, which is what makes a search actionable.
    mutating func selectAllRows() {
        for node in rows {
            selection.insert(node)
        }
        status = "selected \(rows.count) entries"
    }

    mutating func clearSelection() {
        selection.removeAll()
        status = "selection cleared"
    }

    var selectionSize: Int64 {
        selection.totalSize(in: snapshot.root)
    }

    // MARK: - Search

    mutating func beginSearch(mode: MatchMode = .substring) {
        search = SearchState(query: "", mode: mode, isEditing: true, error: nil)
        rows = []
        cursor = 0
        scroll = 0
    }

    mutating func updateSearch(_ transform: (inout String) -> Void) {
        guard var state = search else { return }
        transform(&state.query)
        search = state
        runSearch()
    }

    mutating func commitSearch() {
        guard var state = search else { return }
        state.isEditing = false
        search = state
        if rows.isEmpty { cancelSearch() }
    }

    mutating func cancelSearch() {
        search = nil
        reload()
    }

    private mutating func runSearch() {
        guard var state = search else { return }
        guard !state.query.isEmpty else {
            rows = []
            return
        }

        do {
            let pattern = try Pattern(state.query, mode: state.mode)
            // Only a screenful is ever shown, and a one-letter query matches
            // most of a disk; collecting thousands of rows per keystroke is what
            // makes typing lag behind.
            rows = snapshot.searchTopmost(Filter(pattern: pattern), limit: 500, sortedBy: order)
            state.error = nil
        } catch {
            // An incomplete regex is expected while typing, not an error to shout about.
            rows = []
            state.error = state.mode == .regex ? "incomplete pattern" : "\(error)"
        }
        search = state
        cursor = 0
        scroll = 0
    }

    mutating func reload() {
        if isSearching {
            runSearch()
        } else {
            rows = current.children.sorted(by: order.compare)
        }
        cursor = Swift.min(cursor, Swift.max(0, rows.count - 1))
    }
}
