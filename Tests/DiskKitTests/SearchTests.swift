import Foundation
import Testing
@testable import DiskKit

@Suite("Search")
struct SearchTests {

    /// A tree with node_modules nested inside node_modules.
    private func makeTree() -> Snapshot {
        let root = Node(name: "/work", kind: .directory)
        let app = Node(name: "app", kind: .directory, size: 5_000, fileCount: 3)
        let modules = Node(name: "node_modules", kind: .directory, size: 4_000, fileCount: 2)
        let nested = Node(name: "node_modules", kind: .directory, size: 1_500, fileCount: 1)
        let readme = Node(
            name: "README.md", kind: .file, size: 500, fileCount: 1,
            modified: Date(timeIntervalSince1970: 1_600_000_000),
            accessed: Date(timeIntervalSince1970: 1_600_000_000)
        )

        nested.parent = modules
        modules.children = [nested]
        modules.parent = app
        readme.parent = app
        app.children = [modules, readme]
        app.parent = root
        root.children = [app]
        root.size = app.size
        root.fileCount = app.fileCount
        return Snapshot(root: root, rootPath: "/work")
    }

    @Test("search finds every match anywhere in the tree")
    func findsAllMatches() throws {
        let snapshot = makeTree()
        let matches = snapshot.search(Filter(pattern: try Pattern("node_modules")))
        #expect(matches.count == 2)
    }

    @Test("topmost search skips matches nested inside other matches")
    func skipsNestedMatches() throws {
        let snapshot = makeTree()
        let matches = snapshot.searchTopmost(Filter(pattern: try Pattern("node_modules")))

        #expect(matches.map(\.path) == ["/work/app/node_modules"])
        // Selecting the result must not double-count the nested copy.
        #expect(matches[0].size == 4_000)
    }

    @Test("glob and regex match the way the shell and grep would")
    func matchesGlobAndRegex() throws {
        let snapshot = makeTree()

        #expect(snapshot.search(Filter(pattern: try Pattern("*.md", mode: .glob))).count == 1)
        #expect(snapshot.search(Filter(pattern: try Pattern("*.txt", mode: .glob))).isEmpty)
        #expect(snapshot.search(Filter(pattern: try Pattern("^node_", mode: .regex))).count == 2)
        #expect(snapshot.search(Filter(pattern: try Pattern("READ", mode: .substring))).count == 1)
    }

    @Test("a malformed regex is reported instead of silently matching nothing")
    func rejectsInvalidRegex() {
        #expect(throws: (any Error).self) { try Pattern("[unclosed", mode: .regex) }
    }

    @Test("filters combine size, kind and access time")
    func combinesFilters() throws {
        let snapshot = makeTree()

        #expect(snapshot.search(Filter(minimumSize: 4_500)).map(\.name) == ["app"])
        #expect(snapshot.search(Filter(kinds: [.file])).map(\.name) == ["README.md"])

        let stale = snapshot.search(Filter(notAccessedSince: Date(timeIntervalSince1970: 1_700_000_000)))
        #expect(stale.map(\.name) == ["README.md"])

        let recent = snapshot.search(Filter(notAccessedSince: Date(timeIntervalSince1970: 1_500_000_000)))
        #expect(recent.isEmpty)
    }

    @Test("largest lists the biggest entries below the root")
    func listsLargest() {
        let snapshot = makeTree()
        let largest = snapshot.largest(3)

        #expect(largest.map(\.name) == ["app", "node_modules", "node_modules"])
        #expect(largest.map(\.size) == [5_000, 4_000, 1_500])
        #expect(snapshot.largest(2, kinds: [.file]).map(\.name) == ["README.md"])
    }

    @Test("an empty filter matches nothing rather than everything")
    func emptyFilterMatchesNothing() {
        let snapshot = makeTree()
        #expect(snapshot.search(Filter()).isEmpty)
    }
}
