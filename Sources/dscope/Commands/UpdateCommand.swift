import ArgumentParser
import DiskKit
import Foundation

struct UpdateCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Bring a saved snapshot up to date without rescanning everything.",
        discussion: """
        Asks the filesystem which paths changed since the snapshot was taken and \
        re-measures only those, which usually takes seconds rather than minutes. \
        Falls back to a full scan when the change journal cannot answer — because \
        too much has changed, or the snapshot predates change tracking.
        """
    )

    @Argument(help: "Snapshot to update, in place.")
    var path: String

    @OptionGroup var format: FormatOptions

    @Option(name: .long, help: "Write the result here instead of overwriting.")
    var output: String?

    func run() throws {
        let url = URL(fileURLWithPath: path)
        let snapshot = try SnapshotFile.read(from: url)

        let started = Date()
        let result = IncrementalScan.update(snapshot, options: snapshot.options)
        let elapsed = Date().timeIntervalSince(started)

        let destination = output.map { URL(fileURLWithPath: $0) } ?? url
        try SnapshotFile.write(result.snapshot, to: destination)

        if format.json {
            try Output.emit(
                UpdateReport(
                    root: result.snapshot.rootPath,
                    rescannedDirectories: result.rescanned,
                    deltaBytes: result.delta,
                    humanDelta: signed(result.delta),
                    totalBytes: result.snapshot.totalSize,
                    humanSize: result.snapshot.totalSize.formattedBytes(),
                    seconds: elapsed,
                    fullScanReason: result.fellBackToFullScan?.rawValue,
                    snapshot: destination.path
                ),
                pretty: format.pretty
            )
            return
        }

        if let reason = result.fellBackToFullScan {
            print("rescanned everything (\(reason.rawValue)) in \(String(format: "%.1fs", elapsed))")
        } else if result.rescanned == 0 {
            print("nothing changed since \(snapshot.scannedAt.relativeAge)")
        } else {
            let directories = result.rescanned == 1 ? "1 directory" : "\(result.rescanned) directories"
            print("re-measured \(directories) in \(String(format: "%.1fs", elapsed)), \(signed(result.delta))")
        }
        print("\(result.snapshot.totalSize.formattedBytes())\t\(result.snapshot.rootPath)")
    }

    private func signed(_ delta: Int64) -> String {
        switch delta {
        case 0: "no change"
        case ..<0: "-\((-delta).formattedBytes())"
        default: "+\(delta.formattedBytes())"
        }
    }
}

struct UpdateReport: Codable {
    let root: String
    let rescannedDirectories: Int
    let deltaBytes: Int64
    let humanDelta: String
    let totalBytes: Int64
    let humanSize: String
    let seconds: Double
    let fullScanReason: String?
    let snapshot: String
}
