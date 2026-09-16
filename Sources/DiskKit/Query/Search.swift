import Foundation

public struct SearchResult: Sendable {
    public let path: String
    public let size: Int64
    public let fileCount: Int
    public let kind: Node.Kind
    public let modified: Date?
    public let accessed: Date?
}

public extension Snapshot {

    /// Every node matching the filter, largest first.
    ///
    /// Matches are collected from the whole tree rather than the current
    /// directory, so a search answers "where is this anywhere on disk". The root
    /// itself is never a result: it trivially matches size filters and selecting
    /// it would mean deleting everything scanned.
    func search(_ filter: Filter, limit: Int? = nil, sortedBy order: NodeOrder = .size) -> [Node] {
        guard !filter.isEmpty else { return [] }

        var matches: [Node] = []
        root.walk { node in
            guard node !== root else { return }
            if filter.matches(node) { matches.append(node) }
        }
        matches.sort(by: order.compare)
        if let limit, matches.count > limit {
            matches.removeSubrange(limit...)
        }
        return matches
    }

    /// Matches that are not inside another match.
    ///
    /// Searching for `node_modules` otherwise returns every nested copy as well
    /// as the directory containing them, and selecting all of it would count the
    /// same bytes many times over.
    func searchTopmost(_ filter: Filter, limit: Int? = nil, sortedBy order: NodeOrder = .size) -> [Node] {
        guard !filter.isEmpty else { return [] }

        var matches: [Node] = []
        root.walk(
            descend: { node in
                // Once a directory matches, its contents are part of that match.
                node === root || !filter.matches(node)
            },
            visit: { node in
                guard node !== root else { return }
                if filter.matches(node) { matches.append(node) }
            }
        )
        matches.sort(by: order.compare)
        if let limit, matches.count > limit {
            matches.removeSubrange(limit...)
        }
        return matches
    }

    /// The largest entries worth looking at, none inside another.
    ///
    /// Plain "largest nodes" is useless: the answer is always the chain of
    /// ancestors — `/Users`, then `/Users/you`, then `/Users/you/Library` —
    /// each containing the next, with sizes that sum to several times the disk.
    ///
    /// An entry earns a place only when it is not merely a container for one
    /// big child, so the result is the places where space actually accumulates.
    func largest(_ count: Int, kinds: Set<Node.Kind>? = nil) -> [Node] {
        // A single entry holding most of the tree is a signpost, not an answer:
        // reporting /Users only restates that the disk belongs to somebody.
        let ceiling = Int64(Double(root.size) * 0.5)

        var candidates: [Node] = []
        root.walk { node in
            guard node !== root else { return }
            if let kinds, !kinds.contains(node.kind) { return }
            // A file is an answer whatever its size; only a directory can be a
            // signpost that merely restates where everything lives.
            guard !node.isDirectory || node.size <= ceiling else { return }
            guard accumulatesSpace(node) else { return }
            candidates.append(node)
        }
        candidates.sort { $0.size > $1.size }

        var chosen: [Node] = []
        for node in candidates {
            guard chosen.count < count else { break }
            // Largest first, so an ancestor is always considered before its
            // children; anything under one already chosen would double-count it.
            if chosen.contains(where: { node.isDescendant(of: $0) }) { continue }
            chosen.append(node)
        }
        return chosen
    }

    /// Whether a node holds space in its own right rather than passing it down.
    ///
    /// A directory whose size is almost entirely one child is a waypoint on the
    /// way to that child, and reporting it just buries the real answer.
    private func accumulatesSpace(_ node: Node) -> Bool {
        guard node.isDirectory else { return true }
        guard let largestChild = node.children.max(by: { $0.size < $1.size }) else { return true }
        return Double(largestChild.size) < Double(node.size) * 0.8
    }
}
