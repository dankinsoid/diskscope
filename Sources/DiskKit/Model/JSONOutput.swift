import Foundation

/// A node as reported to a machine consumer.
///
/// This is the tool's public contract: an agent or a script reads these fields,
/// so they are named and shaped independently of the internal `Node`.
public struct NodeJSON: Codable, Sendable {

    public let path: String
    public let name: String
    public let type: String
    public let bytes: Int64
    public let humanSize: String
    public let files: Int
    public let shareOfParent: Double?
    public let modified: Date?
    public let accessed: Date?
    public let unreadable: Bool?
    public let children: [NodeJSON]?

    public init(_ node: Node, includeShare: Bool = true, children: [NodeJSON]? = nil) {
        self.path = node.path
        self.name = node.name
        self.type = switch node.kind {
        case .directory: "directory"
        case .file: "file"
        case .symlink: "symlink"
        }
        self.bytes = node.size
        self.humanSize = node.size.formattedBytes()
        self.files = node.fileCount
        self.shareOfParent = includeShare && node.parent != nil ? node.shareOfParent : nil
        self.modified = node.modified
        self.accessed = node.accessed
        self.unreadable = node.error == nil ? nil : true
        self.children = children
    }

    /// Converts a subtree, stopping at `depth` and omitting anything below `minimumSize`.
    public static func tree(_ node: Node, depth: Int, minimumSize: Int64 = 0) -> NodeJSON {
        guard depth > 0 else { return NodeJSON(node) }
        let children = node.children
            .filter { $0.size >= minimumSize }
            .map { tree($0, depth: depth - 1, minimumSize: minimumSize) }
        return NodeJSON(node, children: children.isEmpty ? nil : children)
    }
}

public struct ScanReportJSON: Codable, Sendable {
    public let root: String
    public let scannedAt: Date
    public let durationSeconds: Double
    public let totalBytes: Int64
    public let humanSize: String
    public let totalFiles: Int
    public let unreadablePaths: [String]
    public let tree: NodeJSON?

    public init(snapshot: Snapshot, tree: NodeJSON?) {
        self.root = snapshot.rootPath
        self.scannedAt = snapshot.scannedAt
        self.durationSeconds = snapshot.duration
        self.totalBytes = snapshot.totalSize
        self.humanSize = snapshot.totalSize.formattedBytes()
        self.totalFiles = snapshot.fileCount
        self.unreadablePaths = snapshot.unreadablePaths
        self.tree = tree
    }
}

public struct SearchReportJSON: Codable, Sendable {
    public let query: String
    public let mode: String
    public let matchCount: Int
    public let totalBytes: Int64
    public let humanSize: String
    public let truncated: Bool
    public let matches: [NodeJSON]

    public init(query: String, mode: MatchMode, matches: [Node], truncated: Bool) {
        self.query = query
        self.mode = mode.rawValue
        self.matchCount = matches.count
        self.totalBytes = matches.reduce(0) { $0 + $1.size }
        self.humanSize = self.totalBytes.formattedBytes()
        self.truncated = truncated
        self.matches = matches.map { NodeJSON($0, includeShare: false) }
    }
}

public extension JSONEncoder {

    /// Stable, human-diffable output: sorted keys and ISO-8601 dates.
    static func reportEncoder(pretty: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                                          : [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

public extension JSONDecoder {

    static func reportDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
