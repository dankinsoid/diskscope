import Foundation

/// Reads and writes snapshots in a compact binary form.
///
/// A scan of a whole disk runs to millions of nodes, where `JSONEncoder` costs
/// both seconds and hundreds of megabytes. Instead names are pooled into a
/// string table and nodes are written in pre-order, each carrying its child
/// count, so the tree rebuilds in a single pass with no back-patching.
public enum SnapshotFile {

    static let magic: UInt32 = 0x64_73_63_70  // "dscp"
    static let version: UInt16 = 1

    public static func write(_ snapshot: Snapshot, to url: URL) throws {
        var strings = StringTable()
        var nodes = Data()
        nodes.reserveCapacity(1 << 20)

        snapshot.root.walk { node in
            nodes.append(record(for: node, strings: &strings))
        }

        var output = Data()
        output.append(uint32: magic)
        output.append(uint16: version)
        output.append(uint16: 0)  // reserved
        output.append(double: snapshot.scannedAt.timeIntervalSince1970)
        output.append(double: snapshot.duration)
        output.append(byte: snapshot.options.crossMountPoints ? 1 : 0)
        output.append(byte: snapshot.options.deduplicateHardLinks ? 1 : 0)
        output.append(string: snapshot.rootPath)
        output.append(data: strings.encoded())
        output.append(uint64: UInt64(snapshot.root.subtreeCount))
        output.append(nodes)

        try output.write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> Snapshot {
        let data = try Data(contentsOf: url)
        var reader = ByteReader(data)

        guard try reader.uint32() == magic else { throw SnapshotError.notASnapshot }
        let fileVersion = try reader.uint16()
        guard fileVersion == version else { throw SnapshotError.unsupportedVersion(fileVersion) }
        _ = try reader.uint16()

        let scannedAt = Date(timeIntervalSince1970: try reader.double())
        let duration = try reader.double()
        let options = ScanOptions(
            crossMountPoints: try reader.byte() == 1,
            deduplicateHardLinks: try reader.byte() == 1
        )
        let rootPath = try reader.string()
        let strings = try StringTable(reader: &reader)
        let count = Int(try reader.uint64())

        guard count > 0 else { throw SnapshotError.corrupted }
        let root = try rebuild(&reader, strings: strings, count: count)

        return Snapshot(
            root: root,
            rootPath: rootPath,
            scannedAt: scannedAt,
            options: options,
            duration: duration
        )
    }

    private static func record(for node: Node, strings: inout StringTable) -> Data {
        var data = Data()
        data.append(uint32: strings.intern(node.name))
        data.append(byte: node.kind.rawValue)
        data.append(byte: node.error.map { $0.rawValue + 1 } ?? 0)
        data.append(uint32: UInt32(node.children.count))
        data.append(uint64: UInt64(bitPattern: node.size))
        data.append(uint64: UInt64(node.fileCount))
        data.append(double: node.modified?.timeIntervalSince1970 ?? .nan)
        data.append(double: node.accessed?.timeIntervalSince1970 ?? .nan)
        return data
    }

    /// Rebuilds the tree from the pre-order stream.
    ///
    /// Iterative for the same reason the format is pre-order: trees nest
    /// thousands of levels deep and recursion would exhaust the stack.
    private static func rebuild(_ reader: inout ByteReader, strings: StringTable, count: Int) throws -> Node {
        /// A parent still waiting for `remaining` more children.
        struct Pending {
            let node: Node
            var remaining: Int
            var children: [Node]
        }

        var stack: [Pending] = []
        var root: Node?
        var decoded = 0

        while decoded < count {
            let node = try decodeNode(&reader, strings: strings)
            decoded += 1

            if stack.isEmpty {
                guard root == nil else { throw SnapshotError.corrupted }
                root = node
            } else {
                node.parent = stack[stack.count - 1].node
                stack[stack.count - 1].children.append(node)
                stack[stack.count - 1].remaining -= 1
            }

            if node.pendingChildCount > 0 {
                var children: [Node] = []
                children.reserveCapacity(node.pendingChildCount)
                stack.append(Pending(node: node, remaining: node.pendingChildCount, children: children))
            }

            // Close out every parent whose children have all arrived.
            while let last = stack.last, last.remaining == 0 {
                last.node.children = last.children
                stack.removeLast()
            }
        }

        guard stack.isEmpty, let root else { throw SnapshotError.corrupted }
        return root
    }

    private static func decodeNode(_ reader: inout ByteReader, strings: StringTable) throws -> Node {
        let nameIndex = try reader.uint32()
        guard let name = strings.string(at: nameIndex) else { throw SnapshotError.corrupted }
        guard let kind = Node.Kind(rawValue: try reader.byte()) else { throw SnapshotError.corrupted }

        let errorCode = try reader.byte()
        let childCount = Int(try reader.uint32())
        let size = Int64(bitPattern: try reader.uint64())
        let fileCount = Int(try reader.uint64())
        let modified = try reader.double()
        let accessed = try reader.double()

        let node = Node(
            name: name,
            kind: kind,
            size: size,
            fileCount: fileCount,
            modified: modified.isNaN ? nil : Date(timeIntervalSince1970: modified),
            accessed: accessed.isNaN ? nil : Date(timeIntervalSince1970: accessed),
            error: errorCode == 0 ? nil : ScanError(rawValue: errorCode - 1)
        )
        node.pendingChildCount = childCount
        return node
    }
}

public enum SnapshotError: Error, CustomStringConvertible {
    case notASnapshot
    case unsupportedVersion(UInt16)
    case corrupted
    case truncated

    public var description: String {
        switch self {
        case .notASnapshot: "not a dscope snapshot"
        case .unsupportedVersion(let version): "snapshot version \(version) is not supported"
        case .corrupted: "snapshot is corrupted"
        case .truncated: "snapshot ends unexpectedly"
        }
    }
}

extension Node {

    /// Number of nodes in this subtree, including itself.
    var subtreeCount: Int {
        var count = 0
        walk { _ in count += 1 }
        return count
    }
}
