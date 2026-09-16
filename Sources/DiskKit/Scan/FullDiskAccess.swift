import Foundation

/// Whether the running process may read the whole disk.
///
/// macOS hides parts of a home directory behind the Full Disk Access privilege,
/// and a scan without it silently reports those places as empty. There is no
/// API to query the privilege, so this reads locations that are protected by it.
public enum FullDiskAccess {

    /// Directories readable only with Full Disk Access granted.
    private static let probes = [
        "Library/Mail",
        "Library/Safari",
        "Library/Cookies",
        "Library/Application Support/com.apple.TCC",
    ]

    public static func isGranted() -> Bool {
        let home = NSHomeDirectory()
        // Absent directories say nothing either way; only a refusal is evidence.
        var sawReadable = false

        for probe in probes {
            let path = home + "/" + probe
            guard FileManager.default.fileExists(atPath: path) else { continue }

            let descriptor = open(path, O_RDONLY | O_DIRECTORY)
            if descriptor >= 0 {
                close(descriptor)
                sawReadable = true
            } else if errno == EACCES || errno == EPERM {
                return false
            }
        }
        return sawReadable
    }

    /// Opens the Full Disk Access list in System Settings.
    public static let settingsURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    public static var instructions: String {
        """
        Grant Full Disk Access so the scan can read every directory:
          1. open \(settingsURL)
          2. enable the terminal app you are running this in
          3. restart that app, then scan again
        """
    }
}
