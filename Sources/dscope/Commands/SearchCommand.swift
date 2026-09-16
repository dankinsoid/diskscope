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
        if filter.glob || filter.regex || filter.path, filter.name == nil, pattern == nil {
            throw ValidationError("--glob, --regex and --path describe a pattern, which was not given")
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

        // Everything matching, so a truncated listing can still report the full
        // size of the category it describes.
        let found = includeNested
            ? snapshot.search(conditions, sortedBy: sort)
            : snapshot.searchTopmost(conditions, sortedBy: sort)

        let truncated = found.count > limit
        let matches = truncated ? Array(found.prefix(limit)) : found

        if format.json {
            try Output.emit(
                SearchReportJSON(
                    query: filter.name ?? pattern ?? "",
                    mode: filter.mode,
                    matches: matches,
                    truncated: truncated,
                    allMatches: found
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
        let total = found.reduce(Int64(0)) { $0 + $1.size }
        if truncated {
            Output.note(
                "showing \(matches.count) of \(found.count) matches;"
                    + " \(total.formattedBytes()) in total"
            )
        } else {
            Output.note("\(matches.count) matches, \(total.formattedBytes()) total")
        }
    }
}

extension MatchMode: ExpressibleByArgument {}
extension NodeOrder: ExpressibleByArgument {}
