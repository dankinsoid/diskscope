import DiskKit
import Foundation

struct ToolDefinition: Encodable {
    let name: String
    let description: String
    let inputSchema: Schema

    struct Schema: Encodable {
        let type = "object"
        let properties: [String: Property]
        let required: [String]
    }

    struct Property: Encodable {
        let type: String
        let description: String
        let `enum`: [String]?

        init(_ type: String, _ description: String, values: [String]? = nil) {
            self.type = type
            self.description = description
            self.enum = values
        }
    }
}

enum Tools {

    static let all: [ToolDefinition] = [
        ToolDefinition(
            name: "scan",
            description: """
                Measure disk usage of a directory and return its tree. Scanning the whole disk \
                takes a few minutes; the result is cached for the other tools, so call this once \
                and then query it. Sizes match `du`: allocated blocks, hard links counted once.
                """,
            inputSchema: .init(
                properties: [
                    "path": .init("string", "Directory to scan. Defaults to the whole disk."),
                    "depth": .init("integer", "Levels of tree to return. Default 2."),
                    "minBytes": .init("integer", "Omit entries smaller than this from the tree."),
                ],
                required: []
            )
        ),
        ToolDefinition(
            name: "search",
            description: """
                Find entries by name anywhere in a scanned tree, largest first. Matches nested \
                inside other matches are omitted, so summing the results never counts bytes twice.
                """,
            inputSchema: .init(
                properties: [
                    "query": .init("string", "Text, glob or regular expression."),
                    "path": .init("string", "Directory or previously scanned path."),
                    "mode": .init("string", "How to match.", values: ["substring", "glob", "regex"]),
                    "minBytes": .init("integer", "Ignore matches smaller than this."),
                    "limit": .init("integer", "Maximum matches. Default 50."),
                ],
                required: ["query"]
            )
        ),
        ToolDefinition(
            name: "largest",
            description: "List the largest entries anywhere in a scanned tree, optionally only ones untouched for a while.",
            inputSchema: .init(
                properties: [
                    "path": .init("string", "Directory or previously scanned path."),
                    "count": .init("integer", "How many to list. Default 20."),
                    "staleDays": .init("integer", "Only entries not accessed for this many days."),
                    "filesOnly": .init("boolean", "List files rather than directories."),
                ],
                required: []
            )
        ),
        ToolDefinition(
            name: "plan_cleanup",
            description: """
                Report what deleting everything matching a pattern would free, and from which \
                paths. Nothing is deleted: this tool cannot delete. Show the paths to the user \
                and let them run `dscope clean <query> <path> --apply` themselves.
                """,
            inputSchema: .init(
                properties: [
                    "query": .init("string", "Text, glob or regular expression to match."),
                    "path": .init("string", "Directory or previously scanned path."),
                    "mode": .init("string", "How to match.", values: ["substring", "glob", "regex"]),
                    "minBytes": .init("integer", "Ignore matches smaller than this."),
                    "except": .init("string", "Keep matches whose path contains this."),
                ],
                required: ["query"]
            )
        ),
        ToolDefinition(
            name: "volumes",
            description: """
                List mounted volumes, APFS local snapshots, and whether Full Disk Access is \
                granted. Use when a scan total is far below the space actually in use: volumes \
                sharing an APFS container, snapshots and unreadable directories hold space that \
                no directory tree contains.
                """,
            inputSchema: .init(properties: [:], required: [])
        ),
    ]

    static func run(name: String, arguments: JSONValue, snapshots: inout [String: Snapshot]) throws -> String {
        switch name {
        case "scan": return try scan(arguments, &snapshots)
        case "search": return try search(arguments, &snapshots)
        case "largest": return try largest(arguments, &snapshots)
        case "plan_cleanup": return try planCleanup(arguments, &snapshots)
        case "volumes": return try volumes()
        default: throw ToolError.unknownTool(name)
        }
    }

    // MARK: - Tools

    private static func scan(_ arguments: JSONValue, _ snapshots: inout [String: Snapshot]) throws -> String {
        let path = arguments["path"]?.stringValue ?? "/"
        let snapshot = try load(path: path, snapshots: &snapshots)
        let depth = arguments["depth"]?.intValue ?? 2
        let minimum = Int64(arguments["minBytes"]?.intValue ?? 0)

        return try encode(
            ScanReportJSON(
                snapshot: snapshot,
                tree: NodeJSON.tree(snapshot.root, depth: depth, minimumSize: minimum)
            )
        )
    }

    private static func search(_ arguments: JSONValue, _ snapshots: inout [String: Snapshot]) throws -> String {
        guard let query = arguments["query"]?.stringValue else { throw ToolError.missingArgument("query") }
        let snapshot = try load(path: arguments["path"]?.stringValue ?? "/", snapshots: &snapshots)
        let mode = MatchMode(rawValue: arguments["mode"]?.stringValue ?? "substring") ?? .substring
        let limit = arguments["limit"]?.intValue ?? 50

        let filter = Filter(
            pattern: try Pattern(query, mode: mode),
            minimumSize: Int64(arguments["minBytes"]?.intValue ?? 0)
        )
        let found = snapshot.searchTopmost(filter, limit: limit + 1)
        let truncated = found.count > limit

        return try encode(
            SearchReportJSON(
                query: query,
                mode: mode,
                matches: truncated ? Array(found.prefix(limit)) : found,
                truncated: truncated
            )
        )
    }

    private static func largest(_ arguments: JSONValue, _ snapshots: inout [String: Snapshot]) throws -> String {
        let snapshot = try load(path: arguments["path"]?.stringValue ?? "/", snapshots: &snapshots)
        let count = arguments["count"]?.intValue ?? 20
        let kinds: Set<Node.Kind>? = arguments["filesOnly"]?.boolValue == true ? [.file] : nil

        let nodes: [Node]
        if let staleDays = arguments["staleDays"]?.intValue {
            let cutoff = Date(timeIntervalSinceNow: -Double(staleDays) * 86_400)
            nodes = snapshot.searchTopmost(
                Filter(kinds: kinds, notAccessedSince: cutoff), limit: count
            )
        } else {
            nodes = snapshot.largest(count, kinds: kinds)
        }

        return try encode(SearchReportJSON(query: "", mode: .substring, matches: nodes, truncated: false))
    }

    private static func planCleanup(_ arguments: JSONValue, _ snapshots: inout [String: Snapshot]) throws -> String {
        guard let query = arguments["query"]?.stringValue else { throw ToolError.missingArgument("query") }
        let path = arguments["path"]?.stringValue ?? "/"
        let snapshot = try load(path: path, snapshots: &snapshots)
        let mode = MatchMode(rawValue: arguments["mode"]?.stringValue ?? "substring") ?? .substring

        let filter = Filter(
            pattern: try Pattern(query, mode: mode),
            minimumSize: Int64(arguments["minBytes"]?.intValue ?? 0)
        )
        let matches = snapshot.searchTopmost(filter)
        let except = arguments["except"]?.stringValue
        let doomed = except.map { keep in matches.filter { !$0.path.contains(keep) } } ?? matches

        var selection = Selection()
        for node in doomed { selection.insert(node) }

        let deleter = Deleter()
        return try encode(
            CleanupPlan(
                query: query,
                wouldFreeBytes: selection.totalSize(in: snapshot.root),
                humanSize: selection.totalSize(in: snapshot.root).formattedBytes(),
                paths: doomed.map { node in
                    CleanupPlan.Entry(
                        path: node.path,
                        bytes: node.size,
                        humanSize: node.size.formattedBytes(),
                        refused: deleter.check(node.path)?.description
                    )
                },
                kept: except.map { keep in matches.filter { $0.path.contains(keep) }.map(\.path) } ?? [],
                applyCommand: "dscope clean '\(query)' \(path) --mode \(mode.rawValue) --apply",
                note: "Nothing was deleted. Show these paths to the user and let them run the command themselves."
            )
        )
    }

    private static func volumes() throws -> String {
        let mounted = VolumeInfo.mounted()
            .filter { $0.used >= 1_073_741_824 }
            .sorted { $0.used > $1.used }

        return try encode(
            VolumesResult(
                volumes: mounted.map {
                    VolumesResult.Volume(
                        mountPoint: $0.mountPoint,
                        storagePool: $0.storagePool,
                        usedBytes: $0.used,
                        capacityBytes: $0.capacity,
                        humanUsed: $0.used.formattedBytes(),
                        readOnly: $0.isReadOnly,
                        diskImageOf: $0.diskImageBackingPath
                    )
                },
                localSnapshots: LocalSnapshots.list(),
                fullDiskAccess: FullDiskAccess.isGranted(),
                fullDiskAccessInstructions: FullDiskAccess.isGranted() ? nil : FullDiskAccess.instructions,
                note: """
                    Volumes sharing a storagePool report the same usedBytes; never sum them. \
                    A volume with diskImageOf set is a mounted image whose bytes are the file \
                    named there, already counted by a scan covering that file.
                    """
            )
        )
    }

    // MARK: - Support

    /// Scans a directory, or returns the tree already scanned for it.
    private static func load(path: String, snapshots: inout [String: Snapshot]) throws -> Snapshot {
        let standardized = (path as NSString).standardizingPath
        if let cached = snapshots[standardized] { return cached }

        // A path inside something already scanned is answered from that tree.
        for (root, snapshot) in snapshots where standardized.hasPrefix(root + "/") {
            if let node = snapshot.root.node(atPath: standardized) {
                return Snapshot(root: node, rootPath: standardized, volume: snapshot.volume)
            }
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory) else {
            throw ToolError.noSuchPath(standardized)
        }

        let snapshot: Snapshot
        if isDirectory.boolValue {
            let scanner = DiskScanner()
            let started = Date()
            let root = scanner.scan(path: standardized)
            snapshot = Snapshot(
                root: root,
                rootPath: standardized,
                options: scanner.options,
                duration: Date().timeIntervalSince(started),
                volume: VolumeInfo(path: standardized)
            )
        } else {
            snapshot = try SnapshotFile.read(from: URL(fileURLWithPath: standardized))
        }
        snapshots[standardized] = snapshot
        return snapshot
    }

    private static func encode(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder.reportEncoder(pretty: true)
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

struct CleanupPlan: Encodable {
    struct Entry: Encodable {
        let path: String
        let bytes: Int64
        let humanSize: String
        let refused: String?
    }

    let query: String
    let wouldFreeBytes: Int64
    let humanSize: String
    let paths: [Entry]
    let kept: [String]
    let applyCommand: String
    let note: String
}

struct VolumesResult: Encodable {
    struct Volume: Encodable {
        let mountPoint: String
        let storagePool: String
        let usedBytes: Int64
        let capacityBytes: Int64
        let humanUsed: String
        let readOnly: Bool
        let diskImageOf: String?
    }

    let volumes: [Volume]
    let localSnapshots: [String]
    let fullDiskAccess: Bool
    let fullDiskAccessInstructions: String?
    let note: String
}

enum ToolError: Error, CustomStringConvertible {
    case unknownTool(String)
    case missingArgument(String)
    case noSuchPath(String)

    var description: String {
        switch self {
        case .unknownTool(let name): "unknown tool '\(name)'"
        case .missingArgument(let name): "missing required argument '\(name)'"
        case .noSuchPath(let path): "no such file or directory: \(path)"
        }
    }
}
