import Foundation

/// A scan result, saved so that later questions are answered without touching the disk.
public struct Snapshot: Sendable {

    public let root: Node
    public let scannedAt: Date
    public let rootPath: String
    public let options: ScanOptions
    public let duration: TimeInterval

    /// What the filesystem reported for the scanned volume at scan time.
    public let volume: VolumeInfo?

    public init(
        root: Node,
        rootPath: String,
        scannedAt: Date = Date(),
        options: ScanOptions = ScanOptions(),
        duration: TimeInterval = 0,
        volume: VolumeInfo? = nil
    ) {
        self.root = root
        self.rootPath = rootPath
        self.scannedAt = scannedAt
        self.options = options
        self.duration = duration
        self.volume = volume
    }

    /// Measured size set against what the volume reports in use.
    public var accounting: SpaceAccounting? {
        volume.map { volume in
            let standardized = (rootPath as NSString).standardizingPath
            return SpaceAccounting(
                volume: volume,
                measured: totalSize,
                unreadableCount: unreadablePaths.count,
                coversWholeVolume: standardized == volume.mountPoint || standardized == "/"
            )
        }
    }

    public var totalSize: Int64 { root.size }
    public var fileCount: Int { root.fileCount }

    /// Directories that could not be read, so their sizes are lower bounds.
    public var unreadablePaths: [String] {
        var paths: [String] = []
        root.walk { node in
            if node.error != nil { paths.append(node.path) }
        }
        return paths
    }
}

public extension Node {

    /// Visits this node and every descendant, parents before children.
    ///
    /// Iterative: real trees reach depths in the thousands, where recursion
    /// overflows the stack.
    func walk(_ visit: (Node) -> Void) {
        var stack = [self]
        while let node = stack.popLast() {
            visit(node)
            stack.append(contentsOf: node.children.reversed())
        }
    }

    /// Visits descendants while `descend` allows going deeper, which keeps large
    /// subtrees from being materialised when only the top of the tree is needed.
    func walk(descend: (Node) -> Bool, visit: (Node) -> Void) {
        var stack = [self]
        while let node = stack.popLast() {
            visit(node)
            guard descend(node) else { continue }
            stack.append(contentsOf: node.children.reversed())
        }
    }

    /// The node at `path`, or nil when the path is outside this tree.
    func node(atPath path: String) -> Node? {
        let rootPath = self.path
        guard path == rootPath || path.hasPrefix(rootPath + "/") else { return nil }

        let relative = String(path.dropFirst(rootPath.count))
        var node = self
        for component in relative.split(separator: "/") {
            guard let next = node.children.first(where: { $0.name == component }) else { return nil }
            node = next
        }
        return node
    }

    /// Path from the root down to this node.
    var ancestors: [Node] {
        var chain: [Node] = []
        var node = parent
        while let current = node {
            chain.append(current)
            node = current.parent
        }
        return chain.reversed()
    }
}
