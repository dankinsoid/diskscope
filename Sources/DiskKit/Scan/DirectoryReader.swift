import Foundation

/// One directory entry as returned by the kernel in a bulk read.
struct RawEntry {
    var name: String
    var kind: Node.Kind
    var allocatedSize: Int64
    var fileID: UInt64
    var linkCount: UInt32
    var modified: Date?
    var accessed: Date?
}

/// Reads directory entries with their metadata in batches via `getattrlistbulk`.
///
/// One syscall returns both names and attributes for many entries, which avoids
/// the per-file `lstat` that dominates the cost of a naive walk.
enum DirectoryReader {

    static func read(path: String) throws(ReadFailure) -> [RawEntry] {
        let fd = open(path, O_RDONLY | O_DIRECTORY, 0)
        guard fd >= 0 else { throw ReadFailure(errno: errno) }
        defer { close(fd) }

        var attrList = attrlist()
        attrList.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrList.commonattr =
            attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
            | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_OBJTYPE)
            | attrgroup_t(ATTR_CMN_MODTIME)
            | attrgroup_t(ATTR_CMN_ACCTIME)
            | attrgroup_t(ATTR_CMN_FILEID)
        attrList.fileattr =
            attrgroup_t(ATTR_FILE_ALLOCSIZE)
            | attrgroup_t(ATTR_FILE_LINKCOUNT)

        var entries: [RawEntry] = []
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while true {
            let count = buffer.withUnsafeMutableBytes { raw in
                getattrlistbulk(fd, &attrList, raw.baseAddress, raw.count, 0)
            }
            guard count >= 0 else { throw ReadFailure(errno: errno) }
            if count == 0 { break }

            buffer.withUnsafeBytes { raw in
                var cursor = raw.baseAddress!
                for _ in 0 ..< count {
                    let length = cursor.loadUnaligned(as: UInt32.self)
                    if let entry = parse(cursor) {
                        entries.append(entry)
                    }
                    cursor += Int(length)
                }
            }
        }
        return entries
    }

    /// Decodes one variable-length entry.
    ///
    /// Fields appear in ascending bitmap-bit order, not in the order they are
    /// listed in `attrlist`, and 64-bit fields are padded to an 8-byte boundary
    /// relative to the start of the entry. Verified against `lstat` in tests.
    private static func parse(_ start: UnsafeRawPointer) -> RawEntry? {
        var cursor = start + MemoryLayout<UInt32>.size

        let returned = cursor.loadUnaligned(as: attribute_set_t.self)
        cursor += MemoryLayout<attribute_set_t>.size

        func align(to alignment: Int) {
            let offset = start.distance(to: cursor)
            cursor = start + (offset + alignment - 1) & ~(alignment - 1)
        }

        guard returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0,
              returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0
        else { return nil }

        let nameRef = cursor.loadUnaligned(as: attrreference_t.self)
        let name = String(cString: (cursor + Int(nameRef.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
        cursor += MemoryLayout<attrreference_t>.size

        let objType = cursor.loadUnaligned(as: fsobj_type_t.self)
        cursor += MemoryLayout<fsobj_type_t>.size

        var modified: Date?
        if returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
            modified = Date(timespec: cursor.loadUnaligned(as: timespec.self))
            cursor += MemoryLayout<timespec>.size
        }

        var accessed: Date?
        if returned.commonattr & attrgroup_t(ATTR_CMN_ACCTIME) != 0 {
            accessed = Date(timespec: cursor.loadUnaligned(as: timespec.self))
            cursor += MemoryLayout<timespec>.size
        }

        var fileID: UInt64 = 0
        if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
            fileID = cursor.loadUnaligned(as: UInt64.self)
            cursor += MemoryLayout<UInt64>.size
        }

        var linkCount: UInt32 = 1
        if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 {
            linkCount = cursor.loadUnaligned(as: UInt32.self)
            cursor += MemoryLayout<UInt32>.size
        }

        var allocatedSize: Int64 = 0
        if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
            align(to: MemoryLayout<off_t>.size)
            allocatedSize = cursor.loadUnaligned(as: off_t.self)
        }

        let kind: Node.Kind
        switch objType {
        case fsobj_type_t(VDIR.rawValue): kind = .directory
        case fsobj_type_t(VLNK.rawValue): kind = .symlink
        default: kind = .file
        }

        return RawEntry(
            name: name,
            kind: kind,
            allocatedSize: allocatedSize,
            fileID: fileID,
            linkCount: linkCount,
            modified: modified,
            accessed: accessed
        )
    }
}

struct ReadFailure: Error {
    let errno: Int32

    var scanError: ScanError {
        errno == EACCES || errno == EPERM ? .permissionDenied : .ioError
    }
}

private extension Date {
    init(timespec: timespec) {
        self.init(timeIntervalSince1970: Double(timespec.tv_sec) + Double(timespec.tv_nsec) / 1e9)
    }
}
