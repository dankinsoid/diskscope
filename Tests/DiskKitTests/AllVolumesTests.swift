import Foundation
import Testing
@testable import DiskKit

@Suite("Scanning every volume")
struct AllVolumesTests {

    @Test("a volume under a synthetic root keeps its absolute path")
    func keepsAbsolutePaths() {
        let root = Node(name: "all volumes", kind: .directory)
        root.isSyntheticRoot = true

        let volume = Node(name: "/", kind: .directory, size: 1_000)
        let child = Node(name: "Users", kind: .directory, size: 900)
        child.parent = volume
        volume.children = [child]
        volume.parent = root
        root.children = [volume]

        // Without this the paths come out as "all volumes//Users", and anything
        // acting on them — deletion above all — would miss.
        #expect(volume.path == "/")
        #expect(child.path == "/Users")
    }

    @Test("a second volume nests under its own mount point")
    func handlesSeveralVolumes() {
        let root = Node(name: "all volumes", kind: .directory)
        root.isSyntheticRoot = true

        let external = Node(name: "/Volumes/Backup", kind: .directory, size: 500)
        let file = Node(name: "archive.zip", kind: .file, size: 500, fileCount: 1)
        file.parent = external
        external.children = [file]
        external.parent = root
        root.children = [external]

        #expect(external.path == "/Volumes/Backup")
        #expect(file.path == "/Volumes/Backup/archive.zip")
    }

    @Test("disk images are left out, since their bytes are counted already")
    func skipsDiskImages() {
        // An image's contents live in the file backing it, which a scan
        // covering that file has measured; scanning the mount counts it twice.
        let scannable = AllVolumes.scannable()

        #expect(scannable.allSatisfy { !$0.isDiskImage })
        #expect(scannable.contains { $0.mountPoint == "/" })
    }

    @Test("volumes sharing a storage pool are represented once")
    func collapsesStoragePools() {
        let scannable = AllVolumes.scannable()
        let pools = scannable.map(\.storagePool)

        // /System/Volumes/Data and / share a pool; walking both would count the
        // same bytes twice, as firmlinks already taught us.
        #expect(Set(pools).count == pools.count)
    }

    @Test("an ordinary tree is unaffected by the synthetic root")
    func leavesOrdinaryTreesAlone() {
        let root = Node(name: "/work", kind: .directory)
        let child = Node(name: "src", kind: .directory)
        child.parent = root
        root.children = [child]

        #expect(!root.isSyntheticRoot)
        #expect(child.path == "/work/src")
    }
}

extension AllVolumesTests {

    @Test("pseudo filesystems and bookkeeping volumes are left out")
    func skipsPseudoFilesystems() {
        let scannable = AllVolumes.scannable()

        // /dev is a kernel interface, and the firmware volumes hold nothing a
        // person put there; walking them costs time and reports nothing.
        #expect(!scannable.contains { $0.mountPoint == "/dev" })
        #expect(!scannable.contains { $0.filesystem == "devfs" })
        #expect(!scannable.contains { $0.mountPoint.hasPrefix("/System/Volumes/xarts") })
    }

    @Test("every scannable volume is large enough to be worth walking")
    func skipsTinyVolumes() {
        #expect(AllVolumes.scannable().allSatisfy { $0.used >= 64 * 1_048_576 })
    }
}
