import Foundation

/// Which mounted volumes are disk images, and what file backs each one.
///
/// A disk image occupies space as a file on another volume. When a scan covered
/// that file, the image's contents are already in the total, and counting the
/// mounted volume again would double them.
///
/// The mounted size is not even the right number to double-count: a compressed
/// image expands when mounted. One simulator runtime here reports 22.9GB
/// mounted against a 9.7GB file on disk.
final class DiskImageRegistry: @unchecked Sendable {

    static let shared = DiskImageRegistry()

    private let lock = NSLock()
    private var backingPaths: [String: String]?

    /// The backing file for `device`, or nil when it is not an image.
    func backingPath(forDevice device: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if backingPaths == nil {
            backingPaths = Self.load()
        }
        let name = (device as NSString).lastPathComponent
        // hdiutil lists the whole-disk device as well as its slices.
        return backingPaths?[name] ?? backingPaths?[Self.wholeDisk(of: name)]
    }

    /// `disk15s1` belongs to whole disk `disk15`.
    private static func wholeDisk(of device: String) -> String {
        guard device.hasPrefix("disk") else { return device }
        guard let sIndex = device.dropFirst(4).firstIndex(of: "s") else { return device }
        return String(device[device.startIndex ..< sIndex])
    }

    /// Parses `hdiutil info`, which lists every attached image and its devices.
    private static func load() -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return [:]
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [:] }

        var result: [String: String] = [:]
        var currentImage: String?

        for line in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("image-path") {
                currentImage = line.split(separator: ":", maxSplits: 1)
                    .last?.trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("/dev/disk"), let image = currentImage {
                let device = line.split(separator: "\t").first.map(String.init) ?? String(line)
                result[(device as NSString).lastPathComponent] = image
            }
        }
        return result
    }
}
