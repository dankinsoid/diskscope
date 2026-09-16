import Foundation

/// APFS local snapshots, which hold space that no directory tree accounts for.
public enum LocalSnapshots {

    /// How much space snapshots hold, when the system will say.
    ///
    /// macOS exposes no per-snapshot figure: snapshots share blocks with the
    /// live filesystem and with each other, so "the size of a snapshot" is not
    /// a well-defined number. `diskutil` reports a purgeable total on some
    /// volumes and nothing on others, so callers must handle nil.
    public static func purgeableBytes(volume path: String = "/") -> Int64? {
        guard let output = run("/usr/sbin/diskutil", ["info", "-plist", path]),
              let plist = try? PropertyListSerialization.propertyList(
                  from: output, options: [], format: nil
              ) as? [String: Any]
        else { return nil }

        for key in ["APFSSnapshotPurgeableSpace", "APFSPurgeableSpace", "PurgeableSpace"] {
            if let value = plist[key] as? NSNumber { return value.int64Value }
        }
        return nil
    }

    /// Snapshot names for the volume containing `path`.
    ///
    /// Shelling out to `tmutil` rather than linking a private framework: this is
    /// the documented interface, and the cost is one process per invocation.
    public static func list(volume path: String = "/") -> [String] {
        guard let data = run("/usr/bin/tmutil", ["listlocalsnapshots", path]) else { return [] }

        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.") }
    }

    private static func run(_ executable: String, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
