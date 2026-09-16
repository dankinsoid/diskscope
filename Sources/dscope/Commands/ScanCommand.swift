import ArgumentParser
import DiskKit
import Foundation

struct ScanCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan a directory and show what is using space."
    )

    @OptionGroup var source: SourceOptions
    @OptionGroup var format: FormatOptions

    @Option(name: .shortAndLong, help: "How many levels to show.")
    var depth = 2

    @Option(
        name: .shortAndLong,
        help: "Hide entries smaller than this, e.g. 1GB. Defaults to 1% of the tree."
    )
    var min: String?

    @Option(name: .long, help: "Write the scan to a snapshot for later exploring.")
    var save: String?

    func run() throws {
        let snapshot = try source.load(quiet: format.json)

        if let save {
            try SnapshotFile.write(snapshot, to: URL(fileURLWithPath: save))
            Output.note("saved snapshot to \(save)")
        }

        let explicitMinimum = try min.map(SizeArgument.parse)

        if format.json {
            // Machine consumers get everything unless they ask for less.
            let tree = NodeJSON.tree(snapshot.root, depth: depth, minimumSize: explicitMinimum ?? 0)
            try Output.emit(ScanReportJSON(snapshot: snapshot, tree: tree), pretty: format.pretty)
            return
        }

        let minimumSize = explicitMinimum ?? Self.defaultThreshold(for: snapshot)
        print(TreeRenderer.render(snapshot.root, depth: depth, minimumSize: minimumSize))

        if explicitMinimum == nil, minimumSize > 0 {
            Output.note("hiding entries under \(minimumSize.formattedBytes()); pass --min 0 to show everything")
        }
        for line in Accounting.lines(for: snapshot) {
            Output.note(line)
        }
    }

    /// A threshold that keeps the tree readable without hiding what matters.
    ///
    /// Printing every entry of a scanned disk runs to thousands of lines, most
    /// of them empty directories. A share of the total keeps the output to
    /// roughly a screenful whatever the size of the tree, and hidden entries are
    /// still summed into a trailing row.
    private static func defaultThreshold(for snapshot: Snapshot) -> Int64 {
        max(1_048_576, snapshot.totalSize / 300)
    }
}
