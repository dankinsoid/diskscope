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

    /// The largest entries anywhere in the tree.
    func largest(_ count: Int, kinds: Set<Node.Kind>? = nil) -> [Node] {
        var nodes: [Node] = []
        root.walk { node in
            guard node !== root else { return }
            if let kinds, !kinds.contains(node.kind) { return }
            nodes.append(node)
        }
        return Array(nodes.sorted { $0.size > $1.size }.prefix(count))
    }
}
