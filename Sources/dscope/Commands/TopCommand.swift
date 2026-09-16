import ArgumentParser
import DiskKit
import Foundation

struct TopCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "top",
        abstract: "List the largest entries anywhere in the tree."
    )

    @OptionGroup var source: SourceOptions
    @OptionGroup var filter: FilterOptions
    @OptionGroup var format: FormatOptions

    @Option(name: .shortAndLong, help: "How many entries to list.")
    var count = 20

    @Option(name: .long, help: "List only entries untouched for this many days; the same as --accessed +Nd.")
    var staleDays: Int?

    func run() throws {
        let snapshot = try source.load(quiet: format.json)

        var conditions = try filter.build()
        if let staleDays {
            conditions.accessed = AgeBound(before: Date(timeIntervalSinceNow: -Double(staleDays) * 86_400))
        }

        // With no conditions the question is simply "what is biggest", which is
        // answered by skipping directories that merely contain one large child.
        let nodes = conditions.isEmpty
            ? snapshot.largest(count)
            : snapshot.searchTopmost(conditions, limit: count, sortedBy: .size)

        if format.json {
            try Output.emit(
                SearchReportJSON(query: "", mode: .substring, matches: nodes, truncated: false),
                pretty: format.pretty
            )
            return
        }

        guard !nodes.isEmpty else {
            Output.note("nothing matched")
            return
        }
        for node in nodes {
            let age = node.accessed.map { "  last used \($0.relativeAge)" } ?? ""
            print("\(node.size.formattedBytes())\t\(node.path)\(age)")
        }
    }
}
