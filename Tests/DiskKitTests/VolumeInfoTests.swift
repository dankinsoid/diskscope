import Foundation
import Testing
@testable import DiskKit

@Suite("VolumeInfo")
struct VolumeInfoTests {

    @Test("reads the volume holding a path")
    func readsVolume() throws {
        let volume = try #require(VolumeInfo(path: NSHomeDirectory()))

        #expect(volume.capacity > 0)
        #expect(volume.used > 0)
        #expect(volume.used <= volume.capacity)
        #expect(!volume.mountPoint.isEmpty)
        #expect(!volume.device.isEmpty)
        #expect(volume.filesystem == "apfs")
    }

    @Test("returns nothing for a path that does not exist")
    func rejectsMissingPath() {
        #expect(VolumeInfo(path: "/nonexistent-\(UUID().uuidString)") == nil)
    }

    @Test("lists mounted volumes including the root")
    func listsMountedVolumes() {
        let volumes = VolumeInfo.mounted()

        #expect(volumes.count > 1)
        #expect(volumes.contains { $0.mountPoint == "/" })
        #expect(volumes.allSatisfy { !$0.device.isEmpty })
    }

    @Test("groups volumes of one APFS container into a single pool")
    func groupsByStoragePool() {
        let data = VolumeInfo(
            mountPoint: "/System/Volumes/Data", device: "/dev/disk3s5", filesystem: "apfs",
            isReadOnly: false, capacity: 100, used: 50, available: 50
        )
        let vm = VolumeInfo(
            mountPoint: "/System/Volumes/VM", device: "/dev/disk3s6", filesystem: "apfs",
            isReadOnly: false, capacity: 100, used: 50, available: 50
        )
        let other = VolumeInfo(
            mountPoint: "/Volumes/External", device: "/dev/disk11s1", filesystem: "apfs",
            isReadOnly: false, capacity: 10, used: 5, available: 5
        )

        #expect(data.storagePool == "disk3")
        #expect(vm.storagePool == data.storagePool)
        #expect(other.storagePool == "disk11")
    }
}

@Suite("SpaceAccounting")
struct SpaceAccountingTests {

    private func volume(used: Int64) -> VolumeInfo {
        VolumeInfo(
            mountPoint: "/System/Volumes/Data", device: "/dev/disk3s5", filesystem: "apfs",
            isReadOnly: false, capacity: 500_000_000_000, used: used, available: 0
        )
    }

    @Test("reports the space a whole-volume scan could not reach")
    func reportsUnaccountedSpace() {
        let accounting = SpaceAccounting(
            volume: volume(used: 467_000_000_000),
            measured: 387_000_000_000,
            unreadableCount: 303,
            coversWholeVolume: true
        )

        #expect(accounting.unaccounted == 80_000_000_000)
        #expect(accounting.isSignificant)
        #expect(abs(accounting.unaccountedShare - 0.171) < 0.01)
    }

    @Test("puts a scan of one directory in the context of the whole volume")
    func reportsShareForPartialScans() {
        let accounting = SpaceAccounting(
            volume: volume(used: 400_000_000_000),
            measured: 60_000_000_000,
            unreadableCount: 0,
            coversWholeVolume: false
        )

        // Knowing a folder is 15% of the disk is what makes its size mean something.
        #expect(accounting.isSignificant)
        #expect(!accounting.coversWholeVolume)
        #expect(abs(accounting.measuredShare - 0.15) < 0.001)
        #expect(accounting.unaccounted == 340_000_000_000)
    }

    @Test("stays quiet when the scan accounts for nearly everything")
    func ignoresSmallGaps() {
        let accounting = SpaceAccounting(
            volume: volume(used: 100_000_000_000),
            measured: 99_500_000_000,
            unreadableCount: 1,
            coversWholeVolume: true
        )

        #expect(!accounting.isSignificant)
    }

    @Test("never reports a negative gap when a scan overshoots")
    func clampsNegativeGap() {
        let accounting = SpaceAccounting(
            volume: volume(used: 100),
            measured: 500,
            unreadableCount: 0,
            coversWholeVolume: true
        )

        #expect(accounting.unaccounted == 0)
        #expect(!accounting.isSignificant)
    }
}
