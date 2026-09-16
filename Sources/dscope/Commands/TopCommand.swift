import ArgumentParser
import DiskKit
import Foundation

struct TopCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "top",
        abstract: "List the largest entries anywhere in the tree."
    )

    @OptionGroup var source: SourceOptions
    @OptionGroup var format: FormatOptions

    @Option(name: .shortAndLong, help: "How many entries to list.")
    var count = 20

    @Flag(name: .long, help: "List files only, ignoring directories.")
    var filesOnly = false

    @Option(name: .long, help: "List only entries untouched for this many days.")
    var staleDays: Int?

    func run() throws {
        let snapshot = try source.load(quiet: format.json)

        var nodes: [Node]
        if let staleDays {
            let cutoff = Date(timeIntervalSinceNow: -Double(staleDays) * 86_400)
            let filter = Filter(
                kinds: filesOnly ? [.file] : nil,
                notAccessedSince: cutoff
            )
            nodes = snapshot.searchTopmost(filter, limit: count, sortedBy: .size)
        } else {
            nodes = snapshot.largest(count, kinds: filesOnly ? [.file] : nil)
        }

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
