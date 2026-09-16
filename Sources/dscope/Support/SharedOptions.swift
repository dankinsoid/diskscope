import ArgumentParser
import DiskKit
import Foundation

/// Where the tree comes from: a fresh scan or a saved snapshot.
struct SourceOptions: ParsableArguments {

    @Argument(help: "Directory to scan, or a snapshot file to read.")
    var path: String = FileManager.default.homeDirectoryForCurrentUser.path

    @Flag(name: .long, help: "Cross mount points, counting other volumes too.")
    var crossMounts = false

    func load(quiet: Bool = false) throws -> Snapshot {
        let url = URL(fileURLWithPath: path)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw ValidationError("no such file or directory: \(path)")
        }

        if !isDirectory.boolValue {
            return try SnapshotFile.read(from: url)
        }

        let scanner = DiskScanner(options: ScanOptions(crossMountPoints: crossMounts))
        let progress = quiet ? nil : ProgressReporter(scanner: scanner)
        progress?.start()

        let started = Date()
        let root = scanner.scan(path: path)
        let duration = Date().timeIntervalSince(started)

        progress?.stop()
        if !quiet {
            Output.note("scanned \(root.fileCount) files in \(String(format: "%.1fs", duration))")
        }
        return Snapshot(root: root, rootPath: path, options: scanner.options, duration: duration)
    }
}

struct FormatOptions: ParsableArguments {

    @Flag(name: .long, help: "Emit JSON instead of text.")
    var json = false

    @Flag(name: .long, help: "Indent JSON output.")
    var pretty = false
}
