import Foundation
import Testing
@testable import DiskKit

@Suite("IncrementalScan", .serialized)
struct IncrementalScanTests {

    private func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dscope-inc-\(UUID().uuidString)")
        for directory in ["a/deep", "b", "c"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(directory), withIntermediateDirectories: true
            )
        }
        try Data(repeating: 1, count: 40_000).write(to: root.appendingPathComponent("a/one.bin"))
        try Data(repeating: 2, count: 20_000).write(to: root.appendingPathComponent("a/deep/two.bin"))
        try Data(repeating: 3, count: 10_000).write(to: root.appendingPathComponent("b/three.bin"))
        return root
    }

    private func scan(_ root: URL) -> Snapshot {
        let position = ChangeJournal.currentPosition()
        let scanner = DiskScanner()
        return Snapshot(
            root: scanner.scan(path: root.path),
            rootPath: root.path,
            volume: VolumeInfo(path: root.path),
            journalPosition: position
        )
    }

    /// The property that matters: an updated snapshot must equal a fresh one.
    private func expectMatchesFullScan(_ updated: Snapshot, _ root: URL, _ label: String) {
        let fresh = DiskScanner().scan(path: root.path)

        #expect(updated.totalSize == fresh.size, "\(label): size")
        #expect(updated.fileCount == fresh.fileCount, "\(label): file count")

        var freshNodes: [String: Int64] = [:]
        fresh.walk { freshNodes[$0.path] = $0.size }
        var updatedNodes: [String: Int64] = [:]
        updated.root.walk { updatedNodes[$0.path] = $0.size }

        #expect(updatedNodes.count == freshNodes.count, "\(label): node count")
        for (path, size) in freshNodes {
            #expect(updatedNodes[path] == size, "\(label): size of \(path)")
        }
    }

    @Test("a file added deep in the tree is picked up, and totals match a full scan")
    func detectsAddedFile() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        Thread.sleep(forTimeInterval: 0.6)
        let snapshot = scan(root)
        let originalSize = snapshot.totalSize
        Thread.sleep(forTimeInterval: 0.6)

        // Three levels down, where the root's own mtime does not move.
        try Data(repeating: 9, count: 100_000)
            .write(to: root.appendingPathComponent("a/deep/added.bin"))
        Thread.sleep(forTimeInterval: 0.8)

        let result = IncrementalScan.update(snapshot)

        #expect(result.fellBackToFullScan == nil)
        #expect(result.snapshot.totalSize > originalSize)
        expectMatchesFullScan(result.snapshot, root, "added file")
    }

    @Test("a deleted subtree is removed, and totals match a full scan")
    func detectsDeletion() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        Thread.sleep(forTimeInterval: 0.6)
        let snapshot = scan(root)
        Thread.sleep(forTimeInterval: 0.6)

        try FileManager.default.removeItem(at: root.appendingPathComponent("a/deep"))
        Thread.sleep(forTimeInterval: 0.8)

        let result = IncrementalScan.update(snapshot)

        #expect(result.fellBackToFullScan == nil)
        #expect(result.snapshot.root.node(atPath: root.appendingPathComponent("a/deep").path) == nil)
        expectMatchesFullScan(result.snapshot, root, "deletion")
    }

    @Test("a newly created directory appears, and totals match a full scan")
    func detectsNewDirectory() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        Thread.sleep(forTimeInterval: 0.6)
        let snapshot = scan(root)
        Thread.sleep(forTimeInterval: 0.6)

        let fresh = root.appendingPathComponent("c/brand-new")
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: false)
        try Data(repeating: 4, count: 60_000).write(to: fresh.appendingPathComponent("payload.bin"))
        Thread.sleep(forTimeInterval: 0.8)

        let result = IncrementalScan.update(snapshot)

        #expect(result.fellBackToFullScan == nil)
        #expect(result.snapshot.root.node(atPath: fresh.path) != nil)
        expectMatchesFullScan(result.snapshot, root, "new directory")
    }

    @Test("an untouched tree needs no rescanning at all")
    func detectsNoChanges() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        Thread.sleep(forTimeInterval: 0.6)
        let snapshot = scan(root)
        Thread.sleep(forTimeInterval: 0.8)

        let result = IncrementalScan.update(snapshot)

        #expect(result.rescanned == 0)
        #expect(result.delta == 0)
        #expect(result.snapshot.totalSize == snapshot.totalSize)
    }

    @Test("falls back to a full scan when the snapshot has no journal position")
    func fallsBackWithoutPosition() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let stale = Snapshot(
            root: DiskScanner().scan(path: root.path),
            rootPath: root.path,
            journalPosition: 0
        )
        let result = IncrementalScan.update(stale)

        #expect(result.fellBackToFullScan == .noPosition)
        expectMatchesFullScan(result.snapshot, root, "fallback")
    }

    @Test("rescans a subtree once when several paths inside it changed")
    func collapsesOverlappingPaths() {
        let paths: Set<String> = [
            "/work/project",
            "/work/project/build",
            "/work/project/build/objects",
            "/work/other",
        ]
        #expect(IncrementalScan.topmost(paths) == ["/work/other", "/work/project"])
    }
}
