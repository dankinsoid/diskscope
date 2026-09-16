import DiskKit
import Foundation

/// Explains the gap between what a scan measured and what the volume reports.
///
/// A directory walk can only find what it is allowed to read, and never sees
/// other volumes or APFS snapshots at all. Left unsaid, that gap reads as a
/// wrong answer.
enum Accounting {

    static func lines(for snapshot: Snapshot) -> [String] {
        var lines: [String] = []

        if !snapshot.unreadablePaths.isEmpty {
            var line = "\(snapshot.unreadablePaths.count) directories could not be read; sizes are lower bounds"
            if !FullDiskAccess.isGranted() {
                line += " — grant Full Disk Access to read them (dscope volumes explains how)"
            }
            lines.append(line)
        }

        lines.append(contentsOf: skippedVolumeLines(for: snapshot))

        guard let accounting = snapshot.accounting, accounting.isSignificant else { return lines }

        let volume = accounting.volume
        let percent = Int((accounting.measuredShare * 100).rounded())

        if accounting.coversWholeVolume {
            // The scan covered everything reachable, so the remainder is space
            // no directory tree contains.
            lines.append(
                "measured \(accounting.measured.formattedBytes()) of \(volume.used.formattedBytes()) in use"
                    + " — \(accounting.unaccounted.formattedBytes()) is not in any directory tree"
            )
            lines.append("run 'dscope volumes' to see the volumes and APFS snapshots holding it")
        } else {
            // A subdirectory: say what share of the disk it accounts for.
            lines.append(
                "this is \(percent)% of the \(volume.used.formattedBytes()) in use on \(volume.mountPoint)"
                    + "; \(accounting.unaccounted.formattedBytes()) is elsewhere"
            )
        }
        return lines
    }

    /// Volumes mounted inside the scanned tree that the walk deliberately skipped.
    ///
    /// Not crossing mount points is what keeps a scan off external disks and
    /// stops firmlinks being counted twice, but silently omitting a 2TB drive
    /// mounted under /Volumes would be its own kind of wrong answer.
    private static func skippedVolumeLines(for snapshot: Snapshot) -> [String] {
        guard !snapshot.options.crossMountPoints else { return [] }

        let root = (snapshot.rootPath as NSString).standardizingPath
        let scannedPool = snapshot.volume?.storagePool

        let skipped = VolumeInfo.mounted().filter { volume in
            guard volume.mountPoint != root else { return false }
            guard root == "/" || volume.mountPoint.hasPrefix(root + "/") else { return false }
            guard volume.storagePool != scannedPool else { return false }
            // Read-only system images (simulator runtimes, cryptexes, mounted
            // disk images) are reported too: they occupy space the user may not
            // realise is mounted.
            return volume.used >= 104_857_600
        }
        guard !skipped.isEmpty else { return [] }

        let total = skipped.reduce(Int64(0)) { $0 + $1.used }
        let names = skipped.sorted { $0.used > $1.used }.prefix(3).map(\.mountPoint)
        let suffix = skipped.count > names.count ? " and \(skipped.count - names.count) more" : ""

        return [
            "\(skipped.count) other volumes were not scanned, holding \(total.formattedBytes()):"
                + " \(names.joined(separator: ", "))\(suffix)",
            "scan one directly, or pass --cross-mounts to include them",
        ]
    }
}
