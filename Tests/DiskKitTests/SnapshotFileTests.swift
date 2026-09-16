import Foundation
import Testing
@testable import DiskKit

@Suite("SnapshotFile")
struct SnapshotFileTests {

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dscope-\(UUID().uuidString).dscope")
    }

    @Test("round-trips a scanned tree")
    func roundTripsTree() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dscope-snap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("nested/deeper"), withIntermediateDirectories: true
        )
        try Data(repeating: 9, count: 60_000).write(to: root.appendingPathComponent("nested/payload.bin"))
        try Data(repeating: 1, count: 2_000).write(to: root.appendingPathComponent("nested/deeper/small.bin"))
        defer { try? FileManager.default.removeItem(at: root) }

        let scanned = DiskScanner().scan(path: root.path)
        let snapshot = Snapshot(root: scanned, rootPath: root.path, duration: 1.5)

        let url = temporaryURL()
        try SnapshotFile.write(snapshot, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let restored = try SnapshotFile.read(from: url)

        #expect(restored.rootPath == snapshot.rootPath)
        #expect(restored.totalSize == snapshot.totalSize)
        #expect(restored.fileCount == snapshot.fileCount)
        #expect(restored.duration == 1.5)
        #expect(abs(restored.scannedAt.timeIntervalSince(snapshot.scannedAt)) < 0.001)

        // Every node must survive with its metadata and its position in the tree.
        var originals: [String: Node] = [:]
        scanned.walk { originals[$0.path] = $0 }
        var restoredCount = 0
        restored.root.walk { node in
            restoredCount += 1
            guard let original = originals[node.path] else {
                Issue.record("unexpected path \(node.path)")
                return
            }
            #expect(node.size == original.size)
            #expect(node.kind == original.kind)
            #expect(node.fileCount == original.fileCount)
            #expect(node.children.count == original.children.count)
        }
        #expect(restoredCount == originals.count)
    }

    @Test("preserves dates, errors and missing values")
    func preservesOptionalFields() throws {
        let root = Node(name: "/root", kind: .directory, size: 100, fileCount: 1)
        let withDates = Node(
            name: "dated",
            kind: .file,
            size: 100,
            fileCount: 1,
            modified: Date(timeIntervalSince1970: 1_700_000_000),
            accessed: Date(timeIntervalSince1970: 1_700_000_500)
        )
        let unreadable = Node(name: "locked", kind: .directory, error: .permissionDenied)
        let undated = Node(name: "bare", kind: .file)
        for child in [withDates, unreadable, undated] { child.parent = root }
        root.children = [withDates, unreadable, undated]

        let url = temporaryURL()
        try SnapshotFile.write(Snapshot(root: root, rootPath: "/root"), to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let restored = try SnapshotFile.read(from: url).root
        #expect(restored.children.count == 3)
        #expect(restored.children[0].modified == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(restored.children[0].accessed == Date(timeIntervalSince1970: 1_700_000_500))
        #expect(restored.children[1].error == .permissionDenied)
        #expect(restored.children[2].modified == nil)
        #expect(restored.children[2].accessed == nil)
    }

    @Test("handles trees far deeper than the stack would allow recursively")
    func handlesDeepTrees() throws {
        let depth = 20_000
        let root = Node.makeTestChain(depth: depth, bytesPerLevel: 4_096)

        let url = temporaryURL()
        try SnapshotFile.write(Snapshot(root: root, rootPath: "/deep"), to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let restored = try SnapshotFile.read(from: url)
        #expect(restored.totalSize == Int64(depth) * 4_096)
        #expect(restored.fileCount == depth)

        var measured = 0
        var node = restored.root
        while let child = node.children.first {
            measured += 1
            node = child
        }
        #expect(measured == depth)
        #expect(node.ancestors.count == depth)
    }

    @Test("rejects files that are not snapshots")
    func rejectsForeignFiles() throws {
        let url = temporaryURL()
        try Data("this is not a snapshot".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: SnapshotError.self) { try SnapshotFile.read(from: url) }
    }

    @Test("rejects a truncated snapshot instead of returning a partial tree")
    func rejectsTruncatedFiles() throws {
        let root = Node(name: "/root", kind: .directory, size: 10)
        let child = Node(name: "child", kind: .file, size: 10, fileCount: 1)
        child.parent = root
        root.children = [child]

        let url = temporaryURL()
        try SnapshotFile.write(Snapshot(root: root, rootPath: "/root"), to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let full = try Data(contentsOf: url)
        try full.prefix(full.count - 12).write(to: url)

        #expect(throws: SnapshotError.self) { try SnapshotFile.read(from: url) }
    }
}
