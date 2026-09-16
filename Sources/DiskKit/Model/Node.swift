import Foundation

/// A single entry in the scanned tree.
///
/// Nodes form a parent-linked tree built once by the scanner and then queried
/// many times by the interface, so every derived value is stored rather than
/// recomputed on access.
public final class Node: @unchecked Sendable {

    public enum Kind: UInt8, Codable, Sendable {
        case directory
        case file
        case symlink
    }

    public let name: String
    public let kind: Kind

    /// Physical bytes on disk, summed over the whole subtree.
    ///
    /// Allocated size, not logical: sparse files and compressed files report
    /// what they actually occupy.
    public internal(set) var size: Int64

    /// Files in the subtree, including this node when it is a file.
    public internal(set) var fileCount: Int

    public internal(set) var modified: Date?
    public internal(set) var accessed: Date?

    public internal(set) var children: [Node]
    public internal(set) weak var parent: Node?

    /// Set when the subtree could not be fully traversed, so `size` is a lower bound.
    public internal(set) var error: ScanError?

    /// Scratch space used while a snapshot is being rebuilt.
    var _pendingChildCount: Int = 0

    init(
        name: String,
        kind: Kind,
        size: Int64 = 0,
        fileCount: Int = 0,
        modified: Date? = nil,
        accessed: Date? = nil,
        children: [Node] = [],
        error: ScanError? = nil
    ) {
        self.name = name
        self.kind = kind
        self.size = size
        self.fileCount = fileCount
        self.modified = modified
        self.accessed = accessed
        self.children = children
        self.error = error
    }

    /// Releases the subtree without recursing.
    ///
    /// ARC frees a parent's `children` array inside the parent's own `deinit`,
    /// so a chain thousands of levels deep unwinds recursively and overflows the
    /// stack. Detaching bottom-up keeps every release shallow.
    deinit {
        guard !children.isEmpty else { return }

        var pending = children
        children = []
        while var node = pending.popLast() {
            // Only take apart a node about to be freed anyway. A node someone
            // else still holds — a subtree re-rooted into its own snapshot —
            // must keep its children.
            guard isKnownUniquelyReferenced(&node), !node.children.isEmpty else { continue }
            pending.append(contentsOf: node.children)
            node.children = []
        }
    }

    public var isDirectory: Bool { kind == .directory }

    /// Absolute path, rebuilt by walking up to the root.
    public var path: String {
        guard let parent else { return name }
        let prefix = parent.path
        return prefix == "/" ? "/" + name : prefix + "/" + name
    }

    public var depth: Int {
        var depth = 0
        var node = parent
        while let current = node {
            depth += 1
            node = current.parent
        }
        return depth
    }

    /// Fraction of the parent's size this node occupies; 1 for the root.
    public var shareOfParent: Double {
        guard let parent, parent.size > 0 else { return 1 }
        return Double(size) / Double(parent.size)
    }
}

public enum ScanError: UInt8, Codable, Sendable {
    case permissionDenied
    case ioError
}

public extension Node {

    /// Builds a single chain of directories, for exercising deep-tree handling.
    ///
    /// Each level holds one file, and sizes are accumulated upwards the way a
    /// real scan would leave them.
    static func makeTestChain(depth: Int, bytesPerLevel: Int64 = 4_096) -> Node {
        let root = Node(name: "/deep", kind: .directory)
        var chain = [root]
        var current = root
        for level in 0 ..< depth {
            let child = Node(name: "level-\(level)", kind: .directory, size: bytesPerLevel, fileCount: 1)
            child.parent = current
            current.children = [child]
            chain.append(child)
            current = child
        }
        for node in chain.dropLast().reversed() {
            node.size = bytesPerLevel + (node.children.first?.size ?? 0)
            node.fileCount = (node.children.first?.fileCount ?? 0) + 1
        }
        root.size -= bytesPerLevel  // The root itself holds no file.
        root.fileCount -= 1
        return root
    }
}

extension Node {

    /// Child count read from a snapshot before the children themselves arrive.
    var pendingChildCount: Int {
        get { _pendingChildCount }
        set { _pendingChildCount = newValue }
    }
}
