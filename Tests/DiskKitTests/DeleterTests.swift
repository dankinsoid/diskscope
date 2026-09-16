import Foundation
import Testing
@testable import DiskKit

@Suite("Deleter")
struct DeleterTests {

    @Test("refuses system locations and the home directory", arguments: [
        "/", "/System", "/System/Library", "/usr/bin", "/bin/sh", "/private/var/db/anything",
    ])
    func refusesProtectedPaths(_ path: String) {
        #expect(Deleter().isProtected(path))
    }

    @Test("refuses the home directory itself but not what is inside it")
    func refusesHomeButNotItsContents() {
        let deleter = Deleter()
        #expect(deleter.isProtected(NSHomeDirectory()))
        #expect(!deleter.isProtected(NSHomeDirectory() + "/Library/Caches/something"))
    }

    @Test("refuses paths that only look safe after normalising them")
    func refusesTraversalPaths() {
        #expect(Deleter().isProtected("/usr/bin/../bin/ls"))
        #expect(Deleter().isProtected("/System/./Library"))
    }

    @Test("reports a refusal instead of deleting a protected path")
    func reportsRefusalWithoutDeleting() {
        let summary = Deleter().delete(paths: ["/System/Library"])

        #expect(summary.deletedCount == 0)
        #expect(summary.failures.count == 1)
        #expect(summary.freedBytes == 0)
        #expect(FileManager.default.fileExists(atPath: "/System/Library"))
    }

    @Test("permanently deletes what it is asked to")
    func deletesPermanently() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dscope-del-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let victim = root.appendingPathComponent("junk")
        try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: false)
        try Data(repeating: 0, count: 4_096).write(to: victim.appendingPathComponent("payload.bin"))

        let summary = Deleter(method: .permanent).delete(
            paths: [victim.path], sizes: [victim.path: 4_096]
        )

        #expect(summary.deletedCount == 1)
        #expect(summary.freedBytes == 4_096)
        #expect(summary.failures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: victim.path))
    }

    @Test("moves to the Trash, leaving the file recoverable")
    func movesToTrash() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("dscope-trash-\(UUID().uuidString).bin")
        try Data(repeating: 7, count: 1_024).write(to: file)

        let summary = Deleter(method: .trash).delete(paths: [file.path], sizes: [file.path: 1_024])

        #expect(summary.deletedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path))

        // The item is expected to be in the Trash rather than gone.
        let trash = try FileManager.default.url(
            for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        let trashed = trash.appendingPathComponent(file.lastPathComponent)
        #expect(FileManager.default.fileExists(atPath: trashed.path))
        try? FileManager.default.removeItem(at: trashed)
    }

    @Test("reports a path that vanished since the scan")
    func reportsMissingPaths() {
        let summary = Deleter(method: .permanent)
            .delete(paths: ["/tmp/dscope-does-not-exist-\(UUID().uuidString)"])

        #expect(summary.deletedCount == 0)
        #expect(summary.failures.first?.error == DeletionRefusal.missing.description)
    }

    @Test("keeps going after one failure")
    func continuesAfterFailure() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("dscope-mixed-\(UUID().uuidString).bin")
        try Data(repeating: 1, count: 2_048).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let summary = Deleter(method: .permanent).delete(
            paths: ["/System/Library", file.path, "/tmp/dscope-missing-\(UUID().uuidString)"],
            sizes: [file.path: 2_048]
        )

        #expect(summary.deletedCount == 1)
        #expect(summary.failures.count == 2)
        #expect(summary.freedBytes == 2_048)
    }
}
