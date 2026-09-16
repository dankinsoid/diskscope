import ArgumentParser
import DiskKit
import Foundation

struct VolumesCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "volumes",
        abstract: "Show mounted volumes and space a directory scan cannot see.",
        discussion: """
        A scan walks one directory tree. Space held by other volumes, by APFS \
        snapshots, or by directories it may not read never appears there. This \
        lists what the filesystem itself reports, so a total that looks too \
        small can be explained rather than guessed at.

        Volumes are not deletable through this tool.
        """
    )

    @OptionGroup var format: FormatOptions

    @Flag(name: .long, help: "Include volumes holding less than 1 GB.")
    var all = false

    func run() throws {
        let volumes = VolumeInfo.mounted()
            .filter { all || $0.used >= 1_073_741_824 }
            .sorted { $0.used > $1.used }

        let snapshots = LocalSnapshots.list()

        if format.json {
            try Output.emit(
                VolumesReport(volumes: volumes, localSnapshots: snapshots),
                pretty: format.pretty
            )
            return
        }

        guard !volumes.isEmpty else {
            Output.note("no volumes found")
            return
        }

        // Volumes in one APFS container share a pool and all report the same
        // used figure, so they are grouped rather than listed as separate totals.
        let pools = Dictionary(grouping: volumes, by: \.storagePool)
            .sorted { ($0.value.first?.used ?? 0) > ($1.value.first?.used ?? 0) }

        for (pool, members) in pools {
            guard let first = members.first else { continue }
            let free = first.capacity - first.used
            print("\(pool)  \(first.used.formattedBytes()) used of \(first.capacity.formattedBytes()), \(free.formattedBytes()) free")
            for volume in members.sorted(by: { $0.mountPoint < $1.mountPoint }) {
                var flags: [String] = []
                if volume.isReadOnly { flags.append("ro") }
                if let backing = volume.diskImageBackingPath {
                    flags.append("image of \((backing as NSString).lastPathComponent)")
                }
                let suffix = flags.isEmpty ? "" : "  (\(flags.joined(separator: ", ")))"
                print("    \(volume.mountPoint)\(suffix)")
            }
        }

        if !snapshots.isEmpty {
            print("")
            let held = LocalSnapshots.purgeableBytes().map { " holding \($0.formattedBytes())" } ?? ""
            print("\(snapshots.count) local APFS snapshots\(held) — space no directory tree shows:")
            for snapshot in snapshots.prefix(10) {
                print("  \(snapshot)")
            }
            // Snapshots share blocks, so only the system can say what deleting
            // one would actually release.
            print("Delete with: tmutil deletelocalsnapshots <name>")
            print("Check what they hold: tmutil listlocalsnapshots / and About This Mac > Storage")
        }
    }
}

struct VolumesReport: Codable {

    struct VolumeJSON: Codable {
        let mountPoint: String
        let device: String
        let filesystem: String
        let readOnly: Bool
        let capacityBytes: Int64
        let usedBytes: Int64
        let availableBytes: Int64
        let humanUsed: String
        let humanCapacity: String
    }

    let volumes: [VolumeJSON]
    let localSnapshots: [String]
    let note: String

    init(volumes: [VolumeInfo], localSnapshots: [String]) {
        self.volumes = volumes.map {
            VolumeJSON(
                mountPoint: $0.mountPoint,
                device: $0.device,
                filesystem: $0.filesystem,
                readOnly: $0.isReadOnly,
                capacityBytes: $0.capacity,
                usedBytes: $0.used,
                availableBytes: $0.available,
                humanUsed: $0.used.formattedBytes(),
                humanCapacity: $0.capacity.formattedBytes()
            )
        }
        self.localSnapshots = localSnapshots
        self.note = "Volumes sharing one APFS container report the same used figure; do not sum them."
    }
}
