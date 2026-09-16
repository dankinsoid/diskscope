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
          dscope search ~/Code --size +1GB --accessed 'over 6m'
          dscope search --snapshot ~/disk.dscope --name node_modules

        Matches are reported largest first. A match inside another match is \
        omitted, so summing the results never counts the same bytes twice — a \
        search for node_modules reports the outermost copy only.
        """
    )

    @Argument(
        help: ArgumentHelp(
            "A pattern to match, or the directory to scan when it is the only one.",
            valueName: "pattern"
        )
    )
    var firstPositional: String?

    @Argument(help: "Directory to scan. Defaults to the whole disk.")
    var secondPositional: String = ""

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

    func run() throws {
        let resolved = resolvePositionals()

        var filter = filter
        if let mode {
            // The older --mode spelling, kept working alongside --glob/--regex.
            filter.glob = mode == .glob
            filter.regex = mode == .regex
        }

        let conditions = try filter.build(defaultPattern: resolved.pattern)
        guard !conditions.isEmpty else {
            throw ValidationError("give something to match: a pattern, --size, --accessed or --modified")
        }

        let source = SourceOptions.forPath(
            resolved.path, snapshot: snapshot, crossMounts: crossMounts, under: under
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
                    query: filter.name ?? resolved.pattern ?? "",
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
            Output.note("showing \(matches.count) of \(found.count) matches; \(total.formattedBytes()) in total")
        } else {
            Output.note("\(matches.count) matches, \(total.formattedBytes()) total")
        }
    }

    /// Works out which positional is the pattern and which is the path.
    ///
    /// With one argument the question is which it is. An explicit `--name`
    /// settles it; otherwise something that exists on disk is the path, since
    /// `search ~/Code --name .build` must not scan the whole disk looking for a
    /// directory named "~/Code".
    ///
    /// Done here rather than in a property, because option groups hold no value
    /// until parsing has finished.
    private func resolvePositionals() -> (pattern: String?, path: String) {
        func existsOnDisk(_ argument: String) -> Bool {
            FileManager.default.fileExists(atPath: (argument as NSString).expandingTildeInPath)
        }

        if !secondPositional.isEmpty {
            return (firstPositional, secondPositional)
        }
        guard let only = firstPositional else {
            return (nil, SourceOptions.wholeDisk)
        }
        if filter.name != nil || existsOnDisk(only) {
            return (nil, only)
        }
        return (only, SourceOptions.wholeDisk)
    }
}

extension MatchMode: ExpressibleByArgument {}
extension NodeOrder: ExpressibleByArgument {}
