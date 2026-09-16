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

    func run() async throws {
        let scanner = DiskScanner()
        let started = Date()
        let root = scanner.scan(path: path)
        let elapsed = Date().timeIntervalSince(started)
        print("\(root.path)  \(root.size) bytes  \(root.fileCount) files  \(String(format: "%.2fs", elapsed))")
        for child in root.children.prefix(15) {
            print("  \(child.size)\t\(child.name)")
        }
    }
}
