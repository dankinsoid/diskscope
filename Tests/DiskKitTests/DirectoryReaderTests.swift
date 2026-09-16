import Foundation
import Testing
@testable import DiskKit

@Suite("DirectoryReader")
struct DirectoryReaderTests {

    @Test("reads names, kinds and sizes of a known directory")
    func readsKnownDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dscope-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(repeating: 0x41, count: 5000).write(to: root.appendingPathComponent("a.bin"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("link").path,
            withDestinationPath: root.appendingPathComponent("a.bin").path
        )

        let entries = try DirectoryReader.read(path: root.path)
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })

        #expect(entries.count == 3)
        #expect(byName["a.bin"]?.kind == .file)
        #expect(byName["sub"]?.kind == .directory)
        #expect(byName["link"]?.kind == .symlink)

        let modified = try #require(byName["a.bin"]?.modified)
        #expect(abs(modified.timeIntervalSinceNow) < 60)

        // The bulk layout is decoded by hand, so every numeric field is checked
        // against lstat rather than against a plausible range.
        for entry in entries {
            var status = stat()
            #expect(lstat(root.appendingPathComponent(entry.name).path, &status) == 0)
            #expect(entry.allocatedSize == Int64(status.st_blocks) * 512, "allocatedSize of \(entry.name)")
            #expect(entry.fileID == UInt64(status.st_ino), "fileID of \(entry.name)")
            if entry.kind != .directory {
                #expect(entry.linkCount == status.st_nlink, "linkCount of \(entry.name)")
            }
        }
    }

    @Test("reports permission errors instead of reporting an empty directory")
    func reportsPermissionDenied() throws {
        #expect(throws: ReadFailure.self) {
            try DirectoryReader.read(path: "/private/var/db/sudo")
        }
    }
}

extension DirectoryReaderTests {

    @Test("decodes hard links and large files consistently with lstat")
    func decodesHardLinksAndLargeFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dscope-links-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let original = root.appendingPathComponent("big.bin")
        try Data(repeating: 0x42, count: 200_000).write(to: original)
        try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("hard.bin"))

        let entries = try DirectoryReader.read(path: root.path)
        #expect(entries.count == 2)

        for entry in entries {
            var status = stat()
            #expect(lstat(root.appendingPathComponent(entry.name).path, &status) == 0)
            #expect(entry.allocatedSize == Int64(status.st_blocks) * 512)
            #expect(entry.linkCount == 2)
        }

        // Both names share one inode, which is what lets the scanner count it once.
        #expect(Set(entries.map(\.fileID)).count == 1)
    }

    @Test("reads a directory with more entries than fit in one bulk call")
    func readsLargeDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dscope-many-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0 ..< 2000 {
            try Data("x".utf8).write(to: root.appendingPathComponent("file-\(index).txt"))
        }

        let entries = try DirectoryReader.read(path: root.path)
        #expect(entries.count == 2000)
        #expect(Set(entries.map(\.name)).count == 2000)
    }
}
