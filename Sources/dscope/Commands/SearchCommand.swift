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

    @Argument(help: "Directory to scan. Defaults to the whole disk.")
    var path: String = SourceOptions.wholeDisk

    @Option(
        name: [.customShort("S"), .long],
        help: ArgumentHelp("Read a saved scan instead of scanning.", valueName: "file")
    )
    var snapshot: String?

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

    func run() throws {
        var filter = filter
        if let mode {
            // The older --mode spelling, kept working alongside --glob/--regex.
            filter.glob = mode == .glob
            filter.regex = mode == .regex
        }
        let conditions = try filter.build(defaultPattern: pattern)
        let source = SourceOptions.forPath(
            path, snapshot: snapshot, crossMounts: crossMounts, under: under
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
                    query: filter.name ?? pattern ?? "",
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
