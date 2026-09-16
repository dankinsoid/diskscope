import Foundation
import Testing
@testable import DiskKit

@Suite("DiskScanner")
struct DiskScannerTests {

    /// Builds a tree and returns its root path.
    private func makeTree(_ build: (URL) throws -> Void) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dscope-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try build(root)
        return root
    }

    private func duSize(of path: String) throws -> Int64 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let kilobytes = String(decoding: data, as: UTF8.self)
            .split(separator: "\t").first.flatMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
        return (kilobytes ?? 0) * 1024
    }

    @Test("totals match du for a nested tree")
    func matchesDu() throws {
        let root = try makeTree { root in
            for directory in ["a", "a/deep", "b"] {
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent(directory), withIntermediateDirectories: true
                )
            }
            try Data(repeating: 1, count: 100_000).write(to: root.appendingPathComponent("a/one.bin"))
            try Data(repeating: 2, count: 30_000).write(to: root.appendingPathComponent("a/deep/two.bin"))
            try Data(repeating: 3, count: 7_000).write(to: root.appendingPathComponent("b/three.bin"))
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let tree = DiskScanner().scan(path: root.path)

        #expect(tree.size == (try duSize(of: root.path)))
        #expect(tree.fileCount == 3)
    }

    @Test("counts a hard-linked file once, like du")
    func deduplicatesHardLinks() throws {
        let root = try makeTree { root in
            let original = root.appendingPathComponent("original.bin")
            try Data(repeating: 7, count: 120_000).write(to: original)
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("nested"), withIntermediateDirectories: false
            )
            try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("nested/same.bin"))
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let tree = DiskScanner().scan(path: root.path)
        #expect(tree.size == (try duSize(of: root.path)))

        let withoutDedup = DiskScanner(options: ScanOptions(deduplicateHardLinks: false)).scan(path: root.path)
        #expect(withoutDedup.size > tree.size)
    }

    @Test("children are ordered by size and linked to their parent")
    func buildsNavigableTree() throws {
        let root = try makeTree { root in
            for (name, size) in [("small", 4_000), ("large", 300_000), ("medium", 50_000)] {
                let directory = root.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                try Data(repeating: 0, count: size).write(to: directory.appendingPathComponent("payload.bin"))
            }
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let tree = DiskScanner().scan(path: root.path)

        #expect(tree.children.map(\.name) == ["large", "medium", "small"])
        #expect(tree.children.allSatisfy { $0.parent === tree })
        #expect(tree.children[0].path == root.appendingPathComponent("large").path)
        #expect(tree.children[0].depth == 1)
        #expect(tree.children[0].shareOfParent > 0.8)
    }

    @Test("records permission failures without aborting the scan")
    func survivesUnreadableDirectories() throws {
        let tree = DiskScanner().scan(path: "/private/var/db")
        #expect(tree.size > 0)

        let unreadable = tree.children.filter { $0.error == .permissionDenied }
        #expect(!unreadable.isEmpty, "expected at least one directory to be unreadable without root")
    }
}
