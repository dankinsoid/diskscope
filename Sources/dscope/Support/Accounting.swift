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
            lines.append("\(snapshot.unreadablePaths.count) directories could not be read; sizes are lower bounds")
        }

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
}
