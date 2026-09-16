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

    /// Entries below the threshold are folded into one row per directory.
    ///
    /// A directory of a thousand entries is unreadable, and most of them are
    /// bytes. Rather than hiding them, the small ones collect into a row that
    /// opens like a folder — so nothing disappears and the list stays legible.
    var foldSmallEntries = true

    /// Directories whose folded row the user has opened.
    private var unfolded: Set<ObjectIdentifier> = []

    /// The row standing in for everything folded away in `current`.
    private(set) var foldedRow: FoldedRow?

    struct FoldedRow {
        let nodes: [Node]
        let bytes: Int64
        /// Index in `rows` where the fold sits.
        let index: Int
    }

    struct SearchState {
        var query: String
        var mode: MatchMode
        var isEditing: Bool
        var error: String?
    }

    init(snapshot: Snapshot) {
        self.snapshot = snapshot
        self.current = snapshot.root
        self.rows = []
        self.cursor = 0
        self.scroll = 0
        reload()
    }

    var selectedNode: Node? {
        guard let index = rowIndex(forCursor: cursor) else { return nil }
        return rows.indices.contains(index) ? rows[index] : nil
    }

    /// Maps a cursor position to an index in `rows`.
    ///
    /// The folded row occupies a line of its own without being a node, so
    /// everything after it sits one line further down than its index.
    func rowIndex(forCursor cursor: Int) -> Int? {
        guard let foldedRow else { return cursor }
        if cursor == foldedRow.index { return nil }
        return cursor > foldedRow.index ? cursor - 1 : cursor
    }

    /// Lines on screen, counting the folded row.
    var displayCount: Int {
        rows.count + (foldedRow == nil ? 0 : 1)
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

    /// Selects every entry hidden behind the fold, so it can be acted on
    /// without expanding it first.
    mutating func selectFolded() {
        guard let foldedRow else { return }
        for node in foldedRow.nodes { selection.insert(node) }
        status = "selected \(foldedRow.nodes.count) smaller entries"
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
        unfolded.remove(ObjectIdentifier(current))
        current = node
        cursor = 0
        scroll = 0
        reload()
    }

    /// Moves the view without moving the cursor, the way a scroll should.
    ///
    /// The cursor is dragged along only when the view would leave it behind, so
    /// scrolling reads as moving the page rather than as pressing an arrow key.
    mutating func scroll(by delta: Int, viewportHeight: Int) {
        guard displayCount > viewportHeight else { return }

        let maximum = Swift.max(0, displayCount - viewportHeight)
        scroll = Swift.max(0, Swift.min(maximum, scroll + delta))

        // Keep the cursor within what is now on screen.
        cursor = Swift.max(scroll, Swift.min(scroll + viewportHeight - 1, cursor))
    }

    mutating func move(by delta: Int) {
        guard displayCount > 0 else { return }
        cursor = Swift.max(0, Swift.min(displayCount - 1, cursor + delta))
    }

    mutating func moveTo(_ index: Int) {
        guard displayCount > 0 else { return }
        cursor = Swift.max(0, Swift.min(displayCount - 1, index))
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
        // Results come from the whole tree, where a fold — which stands for the
        // rest of one directory — has no meaning.
        foldedRow = nil

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
            foldedRow = nil
        } else {
            buildRows()
        }
        cursor = Swift.min(cursor, Swift.max(0, displayCount - 1))
    }

    private mutating func buildRows() {
        let sorted = current.children.sorted(by: order.compare)
        foldedRow = nil

        guard foldSmallEntries, !unfolded.contains(ObjectIdentifier(current)) else {
            rows = sorted
            return
        }

        let threshold = Self.threshold(for: current)
        let large = sorted.filter { $0.size >= threshold }
        let small = sorted.filter { $0.size < threshold }

        // Folding one or two rows away only costs a keystroke to undo.
        guard small.count > 3 else {
            rows = sorted
            return
        }

        rows = large
        foldedRow = FoldedRow(
            nodes: small,
            bytes: small.reduce(0) { $0 + $1.size },
            index: large.count
        )
    }

    /// The size below which entries are folded together.
    ///
    /// A share of the directory rather than a fixed size, so it means the same
    /// thing in a home directory and in a source tree.
    private static func threshold(for directory: Node) -> Int64 {
        Swift.max(1, directory.size / 100)
    }

    /// Whether the cursor is on the folded row.
    var isOnFoldedRow: Bool {
        guard let foldedRow else { return false }
        return cursor == foldedRow.index
    }

    mutating func openFold() {
        unfolded.insert(ObjectIdentifier(current))
        let previousCount = rows.count
        reload()
        cursor = Swift.min(previousCount, Swift.max(0, rows.count - 1))
    }
}
