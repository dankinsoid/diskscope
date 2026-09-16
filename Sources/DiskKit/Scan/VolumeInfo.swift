import Foundation

/// What the filesystem itself says about space, independent of any tree walk.
///
/// A scan can only measure what it is allowed to read, and never sees other
/// volumes at all. Comparing the two is what turns "here is a tree" into an
/// answer to "where did my disk go".
public struct VolumeInfo: Sendable {

    public let mountPoint: String
    public let device: String
    public let filesystem: String
    public let isReadOnly: Bool

    /// Total capacity, as reported for this volume.
    public let capacity: Int64

    /// Bytes in use, the number Finder and `df` show.
    public let used: Int64

    public let available: Int64

    public init(
        mountPoint: String,
        device: String,
        filesystem: String,
        isReadOnly: Bool,
        capacity: Int64,
        used: Int64,
        available: Int64
    ) {
        self.mountPoint = mountPoint
        self.device = device
        self.filesystem = filesystem
        self.isReadOnly = isReadOnly
        self.capacity = capacity
        self.used = used
        self.available = available
    }

    public init?(path: String) {
        var buffer = statfs()
        guard statfs(path, &buffer) == 0 else { return nil }
        self.init(buffer)
    }

    init(_ buffer: statfs) {
        let blockSize = Int64(buffer.f_bsize)
        self.capacity = Int64(buffer.f_blocks) * blockSize
        self.used = Int64(buffer.f_blocks - buffer.f_bfree) * blockSize
        self.available = Int64(buffer.f_bavail) * blockSize
        self.isReadOnly = buffer.f_flags & UInt32(MNT_RDONLY) != 0
        self.mountPoint = Self.string(buffer.f_mntonname)
        self.device = Self.string(buffer.f_mntfromname)
        self.filesystem = Self.string(buffer.f_fstypename)
    }

    /// Reads a fixed-size C character array out of a `statfs` field.
    ///
    /// The tuple must be copied to a local first: taking a pointer into a
    /// temporary leaves it dangling as soon as the call returns.
    private static func string<T>(_ field: T) -> String {
        var copy = field
        return withUnsafeBytes(of: &copy) { raw in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }

    /// Volumes sharing storage report the same used figure, so summing them
    /// overstates usage several times over. This is the pool they belong to.
    ///
    /// APFS names volumes `/dev/diskNsM` within container `diskN`; everything
    /// else is treated as its own pool.
    public var storagePool: String {
        let name = (device as NSString).lastPathComponent
        guard name.hasPrefix("disk"), let sIndex = name.dropFirst(4).firstIndex(of: "s") else {
            return device
        }
        return String(name[name.startIndex ..< sIndex])
    }

    /// Every mounted volume.
    public static func mounted() -> [VolumeInfo] {
        var pointer: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&pointer, MNT_NOWAIT)
        guard count > 0, let pointer else { return [] }

        return (0 ..< Int(count)).map { VolumeInfo(pointer[$0]) }
    }
}

/// What a scan measured, set against what the filesystem reports.
public struct SpaceAccounting: Sendable {

    public let volume: VolumeInfo
    public let measured: Int64
    public let unreadableCount: Int

    /// Whether the scan covered the whole volume rather than a directory in it.
    ///
    /// Comparing a subdirectory against the volume total says only that the rest
    /// of the disk exists, which is noise.
    public let coversWholeVolume: Bool

    public init(volume: VolumeInfo, measured: Int64, unreadableCount: Int, coversWholeVolume: Bool) {
        self.volume = volume
        self.measured = measured
        self.unreadableCount = unreadableCount
        self.coversWholeVolume = coversWholeVolume
    }

    /// Space in use that the scan did not attribute to any path.
    ///
    /// On macOS this is normally the sum of directories the scan could not read,
    /// other volumes sharing the APFS container, and APFS snapshots — none of
    /// which appear in a directory tree.
    public var unaccounted: Int64 {
        max(0, volume.used - measured)
    }

    public var unaccountedShare: Double {
        volume.used > 0 ? Double(unaccounted) / Double(volume.used) : 0
    }

    /// Worth telling the user about rather than leaving them to wonder.
    ///
    /// Reported for a partial scan too: knowing that a folder holds 12% of the
    /// disk is the context that makes its size mean something.
    public var isSignificant: Bool {
        unaccounted > 1_073_741_824 && unaccountedShare > 0.02
    }

    /// Share of the volume's used space this scan accounts for.
    public var measuredShare: Double {
        volume.used > 0 ? Double(measured) / Double(volume.used) : 0
    }
}
