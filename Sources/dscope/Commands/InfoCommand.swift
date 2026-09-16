import ArgumentParser
import DiskKit
import Foundation

struct InfoCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Describe a saved snapshot."
    )

    @Argument(help: "Snapshot file.")
    var path: String

    @OptionGroup var format: FormatOptions

    func run() throws {
        let snapshot = try SnapshotFile.read(from: URL(fileURLWithPath: path))

        if format.json {
            try Output.emit(ScanReportJSON(snapshot: snapshot, tree: nil), pretty: format.pretty)
            return
        }

        print("root        \(snapshot.rootPath)")
        print("scanned     \(snapshot.scannedAt.formatted()) (\(snapshot.scannedAt.relativeAge))")
        print("size        \(snapshot.totalSize.formattedBytes())")
        print("files       \(snapshot.fileCount)")
        print("scan time   \(String(format: "%.1fs", snapshot.duration))")
        if !snapshot.unreadablePaths.isEmpty {
            print("unreadable  \(snapshot.unreadablePaths.count) directories")
        }
    }
}
