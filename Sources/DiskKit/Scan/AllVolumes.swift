import Foundation

/// Scans every mounted volume, not just the one holding the root.
///
/// "The whole computer" is more than `/`: external disks and other filesystems
/// are mounted elsewhere, and a walk from the root never reaches them.
public enum AllVolumes {

    /// Volumes worth scanning as storage in their own right.
    ///
    /// Disk images are left out: their bytes are the file backing them, which a
    /// scan covering that file has already counted. Volumes sharing a storage
    /// pool are represented once, by the mount point a scan can actually walk.
    public static func scannable() -> [VolumeInfo] {
        var byPool: [String: VolumeInfo] = [:]

        for volume in VolumeInfo.mounted() {
            guard !volume.isDiskImage else { continue }
            guard !isPseudoFilesystem(volume) else { continue }

            // Below this a volume is bookkeeping rather than storage, and
            // scanning it costs more than it can ever report.
            guard volume.used >= 64 * 1_048_576 else { continue }

            // Prefer the shallowest mount point of a pool: on macOS the data
            // volume is reachable from "/", so scanning both counts it twice.
            let existing = byPool[volume.storagePool]
            if existing == nil || volume.mountPoint.count < existing!.mountPoint.count {
                byPool[volume.storagePool] = volume
            }
        }
        return byPool.values.sorted { $0.mountPoint < $1.mountPoint }
    }

    /// Whether a volume holds kernel state rather than files worth measuring.
    private static func isPseudoFilesystem(_ volume: VolumeInfo) -> Bool {
        switch volume.filesystem {
        case "devfs", "autofs", "nullfs", "procfs", "fdesc", "lifs", "msdos":
            true
        default:
            // The secure-token and firmware volumes exist for the system's own
            // use and hold nothing a person put there.
            volume.mountPoint.hasPrefix("/System/Volumes/xarts")
                || volume.mountPoint.hasPrefix("/System/Volumes/iSCPreboot")
                || volume.mountPoint.hasPrefix("/System/Volumes/Hardware")
        }
    }

    /// Scans every volume and gathers the results under one root.
    ///
    /// - Parameter progress: called with each volume before it is scanned.
    public static func scan(
        options: ScanOptions = ScanOptions(),
        progress: ((VolumeInfo) -> Void)? = nil,
        scanner: (String) -> Node
    ) -> Node {
        let volumes = scannable()

        // Named for what it is, since it appears at the top of the tree, and
        // marked so the absolute paths below it are left alone.
        let root = Node(name: "all volumes", kind: .directory)
        root.isSyntheticRoot = true

        var children: [Node] = []
        for volume in volumes {
            progress?(volume)
            let tree = scanner(volume.mountPoint)

            // A volume's own mount point names it; the synthetic root above
            // them exists only to hold them together.
            tree.parent = root
            children.append(tree)
        }

        root.children = children.sorted { $0.size > $1.size }
        root.size = children.reduce(0) { $0 + $1.size }
        root.fileCount = children.reduce(0) { $0 + $1.fileCount }
        return root
    }
}
