import Foundation

/// APFS local snapshots, which hold space that no directory tree accounts for.
public enum LocalSnapshots {

    /// Snapshot names for the volume containing `path`.
    ///
    /// Shelling out to `tmutil` rather than linking a private framework: this is
    /// the documented interface, and the cost is one process per invocation.
    public static func list(volume path: String = "/") -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }

        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.") }
    }
}
