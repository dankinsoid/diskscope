import ArgumentParser
import DiskKit
import Foundation

struct SearchCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Find entries by name anywhere in the tree.",
        discussion: """
        Matches are reported largest first. By default a match inside another \
        match is omitted, so selecting the results never counts the same bytes \
        twice — searching for node_modules reports the outermost copy only.
        """
    )

    @Argument(help: "Text, glob or regular expression to look for.")
    var query: String

    @OptionGroup var source: SourceOptions
    @OptionGroup var format: FormatOptions

    @Option(name: .shortAndLong, help: "Match as substring, glob or regex.")
    var mode: MatchMode = .substring

    @Flag(name: .long, help: "Match against the full path, not just the name.")
    var fullPath = false

    @Flag(name: .long, help: "Include matches nested inside other matches.")
    var includeNested = false

    @Option(name: .shortAndLong, help: "Ignore matches smaller than this, e.g. 100MB.")
    var min = "0"

    @Option(name: .shortAndLong, help: "Stop after this many matches.")
    var limit = 100

    @Option(name: .shortAndLong, help: "Sort by size, name, files, modified or accessed.")
    var sort: NodeOrder = .size

    func run() throws {
        let snapshot = try source.load(quiet: format.json)
        let filter = Filter(
            pattern: try Pattern(query, mode: mode, matchesFullPath: fullPath),
            minimumSize: try SizeArgument.parse(min)
        )

        // One extra result reveals whether the limit cut anything off.
        let probe = limit + 1
        let found = includeNested
            ? snapshot.search(filter, limit: probe, sortedBy: sort)
            : snapshot.searchTopmost(filter, limit: probe, sortedBy: sort)

        let truncated = found.count > limit
        let matches = truncated ? Array(found.prefix(limit)) : found

        if format.json {
            try Output.emit(
                SearchReportJSON(query: query, mode: mode, matches: matches, truncated: truncated),
                pretty: format.pretty
            )
            return
        }

        guard !matches.isEmpty else {
            Output.note("no matches for '\(query)'")
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
