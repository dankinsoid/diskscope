import Foundation
import Testing
@testable import DiskKit

@Suite("Disk images")
struct DiskImageTests {

    @Test("identifies mounted images so their bytes are not counted twice")
    func identifiesMountedImages() throws {
        let volumes = VolumeInfo.mounted()

        // Every image must name the file it came from, and that file must exist:
        // it is the path where the scan already counted those bytes.
        for volume in volumes where volume.isDiskImage {
            let backing = try #require(volume.diskImageBackingPath)
            #expect(backing.hasSuffix(".dmg") || backing.hasSuffix(".sparseimage") || backing.hasSuffix(".iso"))
        }

        // The volume the system runs from is never an image.
        let root = try #require(volumes.first { $0.mountPoint == "/" })
        #expect(!root.isDiskImage)
        #expect(root.diskImageBackingPath == nil)
    }

    @Test("maps a volume slice back to the whole disk hdiutil reports")
    func mapsSliceToWholeDisk() {
        // hdiutil lists /dev/disk15 for an image whose volume is /dev/disk15s1.
        let registry = DiskImageRegistry.shared
        let volumes = VolumeInfo.mounted().filter(\.isDiskImage)

        for volume in volumes {
            let slice = (volume.device as NSString).lastPathComponent
            #expect(registry.backingPath(forDevice: slice) != nil, "no backing for \(slice)")
        }
    }
}
