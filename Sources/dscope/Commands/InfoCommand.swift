import ArgumentParser
import DiskKit
import Foundation

struct InfoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "info", abstract: "Describe a snapshot.")

    @Argument var snapshotPath: String

    func run() throws {
        let started = Date()
        let snapshot = try SnapshotFile.read(from: URL(fileURLWithPath: snapshotPath))
        let elapsed = Date().timeIntervalSince(started)
        var nodes = 0
        snapshot.root.walk { _ in nodes += 1 }
        print("root:     \(snapshot.rootPath)")
        print("size:     \(snapshot.totalSize)")
        print("files:    \(snapshot.fileCount)")
        print("nodes:    \(nodes)")
        print("loaded:   \(String(format: "%.2fs", elapsed))")
    }
}
