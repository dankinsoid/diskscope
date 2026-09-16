import Foundation

/// Deduplicates repeated names, which dominate a snapshot: a tree is full of
/// identical `node_modules`, `.build` and `Contents` components.
struct StringTable {

    private var strings: [String] = []
    private var indexByString: [String: UInt32] = [:]

    init() {}

    init(reader: inout ByteReader) throws {
        let count = Int(try reader.uint32())
        strings.reserveCapacity(count)
        for _ in 0 ..< count {
            strings.append(try reader.string())
        }
    }

    mutating func intern(_ string: String) -> UInt32 {
        if let index = indexByString[string] { return index }
        let index = UInt32(strings.count)
        strings.append(string)
        indexByString[string] = index
        return index
    }

    func string(at index: UInt32) -> String? {
        Int(index) < strings.count ? strings[Int(index)] : nil
    }

    func encoded() -> Data {
        var data = Data()
        data.append(uint32: UInt32(strings.count))
        for string in strings {
            data.append(string: string)
        }
        return data
    }
}

struct ByteReader {

    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    private mutating func take(_ count: Int) throws -> Data {
        guard offset + count <= data.endIndex else { throw SnapshotError.truncated }
        defer { offset += count }
        return data[offset ..< offset + count]
    }

    mutating func byte() throws -> UInt8 {
        try take(1).first!
    }

    mutating func uint16() throws -> UInt16 {
        try take(2).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).littleEndian }
    }

    mutating func uint32() throws -> UInt32 {
        try take(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    }

    mutating func uint64() throws -> UInt64 {
        try take(8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian }
    }

    mutating func double() throws -> Double {
        Double(bitPattern: try uint64())
    }

    mutating func string() throws -> String {
        let length = Int(try uint32())
        return String(decoding: try take(length), as: UTF8.self)
    }
}

extension Data {

    mutating func append(byte: UInt8) {
        append(byte)
    }

    mutating func append(uint16: UInt16) {
        Swift.withUnsafeBytes(of: uint16.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(uint32: UInt32) {
        Swift.withUnsafeBytes(of: uint32.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(uint64: UInt64) {
        Swift.withUnsafeBytes(of: uint64.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(double: Double) {
        append(uint64: double.bitPattern)
    }

    mutating func append(string: String) {
        let bytes = Array(string.utf8)
        append(uint32: UInt32(bytes.count))
        append(contentsOf: bytes)
    }

    mutating func append(data: Data) {
        append(contentsOf: data)
    }
}

extension Data {

    /// Volume figures are optional: a snapshot of a path whose volume could not
    /// be read still has a tree worth keeping.
    mutating func append(volume: VolumeInfo?) {
        guard let volume else {
            append(byte: 0)
            return
        }
        append(byte: 1)
        append(string: volume.mountPoint)
        append(string: volume.device)
        append(string: volume.filesystem)
        append(byte: volume.isReadOnly ? 1 : 0)
        append(uint64: UInt64(bitPattern: volume.capacity))
        append(uint64: UInt64(bitPattern: volume.used))
        append(uint64: UInt64(bitPattern: volume.available))
    }
}

extension ByteReader {

    mutating func volume() throws -> VolumeInfo? {
        guard try byte() == 1 else { return nil }
        return VolumeInfo(
            mountPoint: try string(),
            device: try string(),
            filesystem: try string(),
            isReadOnly: try byte() == 1,
            capacity: Int64(bitPattern: try uint64()),
            used: Int64(bitPattern: try uint64()),
            available: Int64(bitPattern: try uint64())
        )
    }
}
