import ArgumentParser
import DiskKit
import Foundation

/// Where the tree comes from: a fresh scan or a saved snapshot.
struct SourceOptions: ParsableArguments {

    static let wholeDisk = "/"

    @Argument(help: "Directory to scan. Defaults to the whole disk.")
    var path: String = SourceOptions.wholeDisk

    @Option(
        name: [.customShort("S"), .long],
        help: ArgumentHelp(
            "Read a saved scan instead of scanning.",
            discussion: "Written by 'dscope scan --save'. Answers in a second where a scan takes minutes.",
            valueName: "file"
        )
    )
    var snapshot: String?

    /// Creates options for a command that takes its path some other way.
    /// Builds options for a command that takes its path some other way.
    ///
    /// Every field is assigned: a property wrapper left untouched by parsing
    /// holds no value at all, and reading one fails at runtime rather than
    /// falling back to a default.
    static func forPath(
        _ path: String,
        snapshot: String? = nil,
        crossMounts: Bool = false,
        allVolumes: Bool = false,
        under: String? = nil
    ) -> SourceOptions {
        var options = SourceOptions()
        options.path = path
        options.snapshot = snapshot
        options.crossMounts = crossMounts
        options.allVolumes = allVolumes
        options.under = under
        options.previousSize = nil
        return options
    }

    @Flag(name: .long, help: "Cross mount points, counting other volumes too.")
    var crossMounts = false

    @Flag(
        name: .long,
        help: "Scan every mounted volume, not only the one holding the given path."
    )
    var allVolumes = false

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
        // A path always means "scan this". A saved scan is named explicitly,
        // so a file and a directory never have to be told apart by guessing.
        if let snapshot {
            let expanded = (snapshot as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded) else {
                throw ValidationError("no such snapshot: \(snapshot)")
            }
            return try narrow(try SnapshotFile.read(from: URL(fileURLWithPath: expanded)))
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw ValidationError("no such file or directory: \(path)")
        }
        guard isDirectory.boolValue else {
            throw ValidationError(
                "\(path) is a file. To read a saved scan, pass it as --snapshot \(path)"
            )
        }

        if allVolumes {
            return try scanEveryVolume(quiet: quiet, summary: summary)
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

    /// Resolves every symlink in a path, including the ones Foundation keeps.
    private func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Scans every mounted volume and gathers them under one root.
    private func scanEveryVolume(quiet: Bool, summary: Bool) throws -> Snapshot {
        let options = ScanOptions(crossMountPoints: crossMounts)
        let journalPosition = ChangeJournal.currentPosition()
        let started = Date()

        var scanners: [DiskScanner] = []
        let root = AllVolumes.scan(options: options) { path in
            let scanner = DiskScanner(options: options)
            scanners.append(scanner)

            let progress = quiet ? nil : ProgressReporter(
                scanner: scanner,
                estimate: ScanEstimate.of(path: path)
            )
            progress?.start()
            defer { progress?.stop() }

            return scanner.scan(path: path)
        }

        let duration = Date().timeIntervalSince(started)
        if !quiet, summary {
            Output.note("scanned \(root.fileCount) files across \(root.children.count) volumes in \(String(format: "%.1fs", duration))")
        }

        return try narrow(
            Snapshot(
                root: root,
                rootPath: "",
                options: options,
                duration: duration,
                volume: VolumeInfo(path: "/"),
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

        // standardizingPath rewrites /private/var to /var, which is a symlink
        // in the tree: narrowing to it reports zero bytes for a directory
        // holding tens of gigabytes. Try the path as written first, and refuse
        // a symlink rather than answering from one.
        let expanded = NSString(string: under).expandingTildeInPath
        let candidates = [expanded, (expanded as NSString).standardizingPath, realPath(expanded)]

        var found: Node?
        var target = expanded
        for candidate in candidates {
            guard let node = snapshot.root.node(atPath: candidate) else { continue }
            if node.kind == .symlink { continue }
            found = node
            target = candidate
            break
        }

        guard let node = found else {
            let symlinked = candidates.compactMap { snapshot.root.node(atPath: $0) }
                .contains { $0.kind == .symlink }
            throw ValidationError(
                symlinked
                    ? "'\(expanded)' is a symlink in this scan; use the path it points at"
                    : "'\(expanded)' is not inside \(snapshot.rootPath)"
            )
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
