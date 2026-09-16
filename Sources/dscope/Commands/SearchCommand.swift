import ArgumentParser
import DiskKit
import Foundation

struct SearchCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Find entries matching a set of conditions.",
        discussion: """
        Conditions combine, in the manner of find(1): a name, a size range and \
        how long ago something was touched are all one query.

          dscope search --name .build --glob --size +500MB
          dscope search --size +1GB --accessed +6m
          dscope search --name node_modules --modified -7d

        Matches are reported largest first. A match inside another match is \
        omitted, so summing the results never counts the same bytes twice — a \
        search for node_modules reports the outermost copy only.
        """
    )

    @Argument(help: ArgumentHelp("Name to match, as with --name.", valueName: "pattern"))
    var pattern: String?

    @Argument(help: "Directory to scan, or a snapshot file to read.")
    var path: String = SourceOptions.wholeDisk

    @Flag(name: .long, help: "Cross mount points, counting other volumes too.")
    var crossMounts = false

    @Option(name: .long, help: "Limit a snapshot to this subtree, e.g. --under ~/Library.")
    var under: String?

    @OptionGroup var filter: FilterOptions
    @OptionGroup var format: FormatOptions

    @Option(name: [.customShort("m"), .long], help: "Match as substring, glob or regex.")
    var mode: MatchMode?

    @Flag(name: .long, help: "Include matches nested inside other matches.")
    var includeNested = false

    @Option(name: .shortAndLong, help: "Stop after this many matches.")
    var limit = 100

    @Option(name: .shortAndLong, help: "Sort by size, name, files, modified or accessed.")
    var sort: NodeOrder = .size

    func validate() throws {
        if filter.name == nil, pattern == nil, !hasNonNameCondition {
            throw ValidationError("give something to match: a pattern, --size, --accessed or --modified")
        }
    }

    private var hasNonNameCondition: Bool {
        !filter.size.isEmpty || !filter.accessed.isEmpty || !filter.modified.isEmpty
            || filter.filesOnly || filter.dirsOnly || filter.unreadable
    }

    /// Whether the first positional is really the path.
    ///
    /// `search --size +1GB ~/disk.dscope` gives one positional, and it is the
    /// path, not a pattern. Anything that resolves to an existing file or
    /// directory is taken as the path when no explicit pattern condition is set.
    private var pathOnlyInvocation: Bool {
        // Only when no second positional was given: with both present the first
        // is the pattern, however much it looks like a path.
        guard let pattern, path == SourceOptions.wholeDisk else { return false }

        // An explicit --name means any positional left over must be the path.
        if filter.name != nil { return true }

        let expanded = (pattern as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded)
    }

    func run() throws {
        var filter = filter
        if let mode {
            // The older --mode spelling, kept working alongside --glob/--regex.
            filter.glob = mode == .glob
            filter.regex = mode == .regex
        }
        let conditions = try filter.build(defaultPattern: pathOnlyInvocation ? nil : pattern)
        let source = SourceOptions.forPath(
            pathOnlyInvocation ? (pattern ?? path) : path, crossMounts: crossMounts, under: under
        )
        let snapshot = try source.load(quiet: format.json)

        // One extra result reveals whether the limit cut anything off.
        let found = includeNested
            ? snapshot.search(conditions, limit: limit + 1, sortedBy: sort)
            : snapshot.searchTopmost(conditions, limit: limit + 1, sortedBy: sort)

        let truncated = found.count > limit
        let matches = truncated ? Array(found.prefix(limit)) : found

        if format.json {
            try Output.emit(
                SearchReportJSON(
                    query: filter.name ?? (pathOnlyInvocation ? "" : pattern ?? ""),
                    mode: filter.mode,
                    matches: matches,
                    truncated: truncated
                ),
                pretty: format.pretty
            )
            return
        }

        guard !matches.isEmpty else {
            Output.note("nothing matched")
            return
        }
        for node in matches {
            print("\(node.size.formattedBytes())\t\(node.path)")
        }
        let total = matches.reduce(Int64(0)) { $0 + $1.size }
        Output.note("\(matches.count) matches, \(total.formattedBytes()) total\(truncated ? " (limited)" : "")")
    }
}

extension MatchMode: ExpressibleByArgument {}
extension NodeOrder: ExpressibleByArgument {}
