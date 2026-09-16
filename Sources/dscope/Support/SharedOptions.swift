import ArgumentParser
import DiskKit
import Foundation

/// Where the tree comes from: a fresh scan or a saved snapshot.
struct SourceOptions: ParsableArguments {

    static let wholeDisk = "/"

    @Argument(help: "Directory to scan, or a snapshot file to read. Defaults to the whole disk.")
    var path: String = SourceOptions.wholeDisk

    @Flag(name: .long, help: "Cross mount points, counting other volumes too.")
    var crossMounts = false

    @Option(name: .long, help: "Limit a snapshot to this subtree, e.g. --under ~/Library.")
    var under: String?

    /// Size a previous scan of this path reported, when one is at hand.
    ///
    /// Used only to give the progress bar a denominator.
    var previousSize: Int64?

    /// Loads the tree, printing progress unless `quiet`.
    ///
    /// - Parameter summary: whether to report what was scanned when finished.
    ///   An interactive browser draws over that line immediately, so it only
    ///   adds a flash of text.
    func load(quiet: Bool = false, summary: Bool = true) throws -> Snapshot {
        let url = URL(fileURLWithPath: path)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw ValidationError("no such file or directory: \(path)")
        }

        if !isDirectory.boolValue {
            let snapshot = try SnapshotFile.read(from: url)
            return try narrow(snapshot)
        }

        let scanner = DiskScanner(options: ScanOptions(crossMountPoints: crossMounts))
        let progress = quiet
            ? nil
            : ProgressReporter(
                scanner: scanner,
                estimate: ScanEstimate.of(path: path, previous: previousSize)
            )
        progress?.start()

        // Taken before walking: a change made mid-scan is then replayed by the
        // next update rather than missed by both.
        let journalPosition = ChangeJournal.currentPosition()
        let started = Date()
        let root = scanner.scan(path: path)
        let duration = Date().timeIntervalSince(started)

        progress?.stop()
        if !quiet, summary {
            Output.note("scanned \(root.fileCount) files in \(String(format: "%.1fs", duration))")
        }
        return try narrow(
            Snapshot(
                root: root,
                rootPath: path,
                options: scanner.options,
                duration: duration,
                volume: VolumeInfo(path: path),
                journalPosition: journalPosition
            )
        )
    }

    /// Restricts a snapshot to the subtree named by `--under`.
    ///
    /// Re-rooting a saved scan is the whole point of saving it: looking inside
    /// one directory should not mean printing the entire disk and filtering.
    private func narrow(_ snapshot: Snapshot) throws -> Snapshot {
        guard let under else { return snapshot }

        let target = (NSString(string: under).expandingTildeInPath as NSString).standardizingPath
        guard let node = snapshot.root.node(atPath: target) else {
            throw ValidationError("'\(target)' is not inside \(snapshot.rootPath)")
        }
        return Snapshot(
            root: node,
            rootPath: target,
            scannedAt: snapshot.scannedAt,
            options: snapshot.options,
            duration: snapshot.duration,
            volume: snapshot.volume
        )
    }
}

struct FormatOptions: ParsableArguments {

    @Flag(name: .long, help: "Emit JSON instead of text.")
    var json = false

    @Flag(name: .long, help: "Indent JSON output.")
    var pretty = false
}
