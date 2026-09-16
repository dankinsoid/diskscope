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

    /// What the volume reports, set against what the scan could measure.
    ///
    /// Present so a consumer can tell "this is all the space in use" from "this
    /// is what a directory walk could reach", which differ by a lot on macOS.
    public struct AccountingJSON: Codable, Sendable {
        public let volumeMountPoint: String
        public let volumeUsedBytes: Int64
        public let volumeCapacityBytes: Int64
        public let volumeAvailableBytes: Int64
        public let measuredBytes: Int64
        public let unaccountedBytes: Int64
        public let humanUnaccounted: String
        public let unreadableDirectories: Int
        public let coversWholeVolume: Bool
        public let measuredShareOfVolume: Double
        public let explanation: String?

        init(_ accounting: SpaceAccounting) {
            self.volumeMountPoint = accounting.volume.mountPoint
            self.volumeUsedBytes = accounting.volume.used
            self.volumeCapacityBytes = accounting.volume.capacity
            self.volumeAvailableBytes = accounting.volume.available
            self.measuredBytes = accounting.measured
            self.unaccountedBytes = accounting.unaccounted
            self.humanUnaccounted = accounting.unaccounted.formattedBytes()
            self.unreadableDirectories = accounting.unreadableCount
            self.coversWholeVolume = accounting.coversWholeVolume
            self.measuredShareOfVolume = accounting.measuredShare
            self.explanation = accounting.coversWholeVolume
                ? "Space in use that no directory tree contains: other volumes sharing the container, APFS snapshots, or directories that could not be read. See 'dscope volumes'."
                : "This scan covers one directory; the rest is the other contents of the volume."
        }
    }

    public let root: String
    public let scannedAt: Date
    public let durationSeconds: Double
    public let totalBytes: Int64
    public let humanSize: String
    public let totalFiles: Int
    public let unreadableCount: Int

    /// A sample rather than the whole list: a disk scan hits hundreds of these,
    /// and printing them all buries the fields a caller actually reads.
    public let unreadablePaths: [String]
    public let accounting: AccountingJSON?
    public let tree: NodeJSON?

    public init(snapshot: Snapshot, tree: NodeJSON?, unreadableSampleSize: Int = 10) {
        self.root = snapshot.rootPath
        self.scannedAt = snapshot.scannedAt
        self.durationSeconds = snapshot.duration
        self.totalBytes = snapshot.totalSize
        self.humanSize = snapshot.totalSize.formattedBytes()
        self.totalFiles = snapshot.fileCount
        let unreadable = snapshot.unreadablePaths
        self.unreadableCount = unreadable.count
        self.unreadablePaths = Array(unreadable.prefix(unreadableSampleSize))
        self.accounting = snapshot.accounting.map(AccountingJSON.init)
        self.tree = tree
    }
}

public struct SearchReportJSON: Codable, Sendable {
    public let query: String
    public let mode: String

    /// Matches listed, which `--limit` may have cut short.
    public let matchCount: Int

    /// Matches found, whatever the limit.
    public let totalMatchCount: Int

    /// Size of every match, not only the listed ones.
    ///
    /// A truncated listing that reported only what it printed would understate
    /// a category by however much was cut — for one query here, threefold.
    public let totalBytes: Int64
    public let humanSize: String

    /// Size of the matches actually listed.
    public let listedBytes: Int64

    public let truncated: Bool
    public let matches: [NodeJSON]

    public init(query: String, mode: MatchMode, matches: [Node], truncated: Bool, allMatches: [Node]? = nil) {
        let everything = allMatches ?? matches

        self.query = query
        self.mode = mode.rawValue
        self.matchCount = matches.count
        self.totalMatchCount = everything.count
        self.totalBytes = everything.reduce(0) { $0 + $1.size }
        self.humanSize = self.totalBytes.formattedBytes()
        self.listedBytes = matches.reduce(0) { $0 + $1.size }
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
