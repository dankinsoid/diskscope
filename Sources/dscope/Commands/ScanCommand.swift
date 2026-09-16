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

    @Option(name: .shortAndLong, help: "Hide entries smaller than this, e.g. 1GB.")
    var min = "0"

    @Option(name: .long, help: "Write the scan to a snapshot for later exploring.")
    var save: String?

    func run() throws {
        let minimumSize = try SizeArgument.parse(min)
        let snapshot = try source.load(quiet: format.json)

        if let save {
            try SnapshotFile.write(snapshot, to: URL(fileURLWithPath: save))
            Output.note("saved snapshot to \(save)")
        }

        if format.json {
            let tree = NodeJSON.tree(snapshot.root, depth: depth, minimumSize: minimumSize)
            try Output.emit(ScanReportJSON(snapshot: snapshot, tree: tree), pretty: format.pretty)
        } else {
            print(TreeRenderer.render(snapshot.root, depth: depth, minimumSize: minimumSize))
            for line in Accounting.lines(for: snapshot) {
                Output.note(line)
            }
        }
    }
}
