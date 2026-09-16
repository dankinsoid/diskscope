import Foundation
import Testing
@testable import DiskKit

@Suite("ChangeJournal", .serialized)
struct ChangeJournalTests {

    @Test("reports a directory that changed after the recorded position")
    func reportsChangedDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dscope-fse-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("deep/inner"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        // Let the creation settle so it belongs to the past, not to the window.
        Thread.sleep(forTimeInterval: 0.6)
        let position = ChangeJournal.currentPosition()
        #expect(position > 0)

        // Change something several levels down, where mtime on the root would
        // not move at all.
        try Data(repeating: 1, count: 1_000)
            .write(to: root.appendingPathComponent("deep/inner/added.bin"))
        Thread.sleep(forTimeInterval: 0.6)

        let outcome = ChangeJournal.changes(under: root.path, since: position, timeout: 8)

        guard case .changed(let directories) = outcome else {
            Issue.record("expected changes, got \(outcome)")
            return
        }
        // The temporary directory lives under a symlink, and FSEvents reports
        // the real path — the same trap the implementation has to handle.
        let resolved = realpath(root.path, nil).map { pointer -> String in
            defer { free(pointer) }
            return String(cString: pointer)
        } ?? root.path

        #expect(
            directories.contains { $0.hasPrefix(resolved) },
            "expected a path under \(resolved), got \(directories)"
        )
    }

    @Test("reports nothing when nothing changed")
    func reportsNoChanges() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dscope-fse-quiet-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        Thread.sleep(forTimeInterval: 0.6)
        let position = ChangeJournal.currentPosition()
        Thread.sleep(forTimeInterval: 0.6)

        let outcome = ChangeJournal.changes(under: root.path, since: position, timeout: 8)

        guard case .changed(let directories) = outcome else {
            Issue.record("expected an empty change set, got \(outcome)")
            return
        }
        #expect(directories.isEmpty)
    }

    @Test("refuses to answer without a recorded position")
    func refusesWithoutPosition() {
        let outcome = ChangeJournal.changes(under: "/tmp", since: 0)

        guard case .unusable(let reason) = outcome else {
            Issue.record("expected to be unusable")
            return
        }
        #expect(reason == .noPosition)
    }

    @Test("gives up rather than replaying an enormous history")
    func givesUpOnLongHistory() {
        // Position 1 means "everything the journal still holds", which is far
        // more than it is ever worth replaying.
        let outcome = ChangeJournal.changes(under: "/", since: 1, limit: 50, timeout: 8)

        guard case .unusable(let reason) = outcome else {
            Issue.record("expected to give up, got \(outcome)")
            return
        }
        #expect(reason == .tooOld || reason == .dropped)
    }
}
