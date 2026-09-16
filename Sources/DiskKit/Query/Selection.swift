import Foundation

/// Nodes marked for deletion.
///
/// Selecting a directory implies its whole subtree, so a node inside an already
/// selected directory is redundant. The set keeps only the topmost selected
/// nodes, which is what makes the freed-space total correct: counting both a
/// directory and something inside it would double-count those bytes.
public struct Selection: Sendable {

    private var paths: Set<String> = []

    public init() {}

    public var isEmpty: Bool { paths.isEmpty }
    public var count: Int { paths.count }
    public var selectedPaths: [String] { paths.sorted() }

    public func contains(_ node: Node) -> Bool {
        paths.contains(node.path)
    }

    /// True when the node is selected outright or sits inside a selected directory.
    public func covers(_ node: Node) -> Bool {
        if paths.contains(node.path) { return true }
        var current: Node? = node.parent
        while let node = current {
            if paths.contains(node.path) { return true }
            current = node.parent
        }
        return false
    }

    public mutating func insert(_ node: Node) {
        let path = node.path
        guard !coversPath(path) else { return }
        paths = paths.filter { !$0.hasPrefix(path + "/") }
        paths.insert(path)
    }

    public mutating func remove(_ node: Node) {
        let path = node.path
        if paths.remove(path) != nil { return }

        // Deselecting inside a selected directory keeps the rest of that
        // directory selected: the exception is carved out of the parent.
        guard let selectedAncestor = ancestorPath(of: path) else { return }
        paths.remove(selectedAncestor)
        for sibling in siblingPaths(from: node, upTo: selectedAncestor) {
            paths.insert(sibling)
        }
    }

    public mutating func toggle(_ node: Node) {
        covers(node) ? remove(node) : insert(node)
    }

    public mutating func removeAll() {
        paths.removeAll()
    }

    /// Bytes freed if everything selected were deleted.
    public func totalSize(in root: Node) -> Int64 {
        paths.reduce(into: Int64(0)) { total, path in
            total += root.node(atPath: path)?.size ?? 0
        }
    }

    public func nodes(in root: Node) -> [Node] {
        paths.compactMap { root.node(atPath: $0) }
    }

    private func coversPath(_ path: String) -> Bool {
        paths.contains(path) || ancestorPath(of: path) != nil
    }

    private func ancestorPath(of path: String) -> String? {
        paths.first { path.hasPrefix($0 + "/") }
    }

    /// Everything under `ancestor` on the way down to `node`, except that path.
    ///
    /// Expanding a selected ancestor into its siblings is what lets a single
    /// exception be removed without losing the rest of the selection.
    private func siblingPaths(from node: Node, upTo ancestor: String) -> [String] {
        var result: [String] = []
        var current: Node? = node
        while let child = current, child.path != ancestor {
            guard let parent = child.parent else { break }
            for sibling in parent.children where sibling.path != child.path {
                result.append(sibling.path)
            }
            current = parent
        }
        return result
    }
}
