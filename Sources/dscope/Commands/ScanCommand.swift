import ArgumentParser
import DiskKit
import Foundation

struct ScanCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan a directory tree and print it."
    )

    @Argument(help: "Root to scan.")
    var path: String = FileManager.default.homeDirectoryForCurrentUser.path

    @Option(name: .customLong("save"), help: "Write the scan to a snapshot file.")
    var savePath: String?

    func run() async throws {
        let scanner = DiskScanner()
        let started = Date()
        let root = scanner.scan(path: path)
        let elapsed = Date().timeIntervalSince(started)
        print("\(root.path)  \(root.size) bytes  \(root.fileCount) files  \(String(format: "%.2fs", elapsed))")

        if let savePath {
            let snapshot = Snapshot(root: root, rootPath: path, duration: elapsed)
            let writeStarted = Date()
            try SnapshotFile.write(snapshot, to: URL(fileURLWithPath: savePath))
            print("saved in \(String(format: "%.2fs", Date().timeIntervalSince(writeStarted)))")
        }
    }
}
