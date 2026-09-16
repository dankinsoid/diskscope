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

        let stale = snapshot.search(
            Filter(accessed: AgeBound(before: Date(timeIntervalSince1970: 1_700_000_000)))
        )
        #expect(stale.map(\.name) == ["README.md"])

        let recent = snapshot.search(
            Filter(accessed: AgeBound(before: Date(timeIntervalSince1970: 1_500_000_000)))
        )
        #expect(recent.isEmpty)
    }

    @Test("largest never lists an entry inside another")
    func listsLargestWithoutNesting() {
        let snapshot = makeTree()
        let largest = snapshot.largest(5)

        // /work/app holds almost everything and would otherwise head the list,
        // followed by the copies of itself on the way down.
        for (index, node) in largest.enumerated() {
            for other in largest[..<index] {
                #expect(!node.isDescendant(of: other), "\(node.path) is inside \(other.path)")
            }
        }

        // Summing the result must never exceed what was scanned.
        #expect(largest.reduce(Int64(0)) { $0 + $1.size } <= snapshot.totalSize)
        #expect(snapshot.largest(2, kinds: [.file]).map(\.name) == ["README.md"])
    }

    @Test("largest skips a directory that is merely a wrapper for one child")
    func skipsPassThroughDirectories() {
        let root = Node(name: "/disk", kind: .directory)
        let wrapper = Node(name: "wrapper", kind: .directory, size: 10_000, fileCount: 1)
        let payload = Node(name: "payload.bin", kind: .file, size: 9_900, fileCount: 1)
        let spread = Node(name: "spread", kind: .directory, size: 8_000, fileCount: 2)
        let halfA = Node(name: "a.bin", kind: .file, size: 4_000, fileCount: 1)
        let halfB = Node(name: "b.bin", kind: .file, size: 4_000, fileCount: 1)

        payload.parent = wrapper
        wrapper.children = [payload]
        for half in [halfA, halfB] { half.parent = spread }
        spread.children = [halfA, halfB]
        for child in [wrapper, spread] { child.parent = root }
        root.children = [wrapper, spread]
        root.size = 18_000

        let largest = Snapshot(root: root, rootPath: "/disk").largest(4)

        // 'wrapper' only passes its size down to one file, so the file is the
        // useful answer; 'spread' genuinely accumulates and is reported itself.
        #expect(largest.contains { $0 === payload })
        #expect(largest.contains { $0 === spread })
        #expect(!largest.contains { $0 === wrapper })
    }

    @Test("an empty filter matches nothing rather than everything")
    func emptyFilterMatchesNothing() {
        let snapshot = makeTree()
        #expect(snapshot.search(Filter()).isEmpty)
    }
}

extension SearchTests {

    @Test("substring matching is case-insensitive both ways")
    func matchesRegardlessOfCase() throws {
        let snapshot = makeTreeForCase()

        #expect(snapshot.search(Filter(pattern: try Pattern("readme"))).count == 1)
        #expect(snapshot.search(Filter(pattern: try Pattern("README"))).count == 1)
        #expect(snapshot.search(Filter(pattern: try Pattern("ReAdMe"))).count == 1)
        #expect(snapshot.search(Filter(pattern: try Pattern("DERIVED"))).count == 1)
    }

    @Test("non-ASCII queries still match")
    func matchesNonASCII() throws {
        let snapshot = makeTreeForCase()

        #expect(snapshot.search(Filter(pattern: try Pattern("Документы"))).count == 1)
        #expect(snapshot.search(Filter(pattern: try Pattern("кумен"))).count == 1)
    }

    @Test("a query longer than the name matches nothing")
    func rejectsOverlongQuery() throws {
        let snapshot = makeTreeForCase()
        #expect(snapshot.search(Filter(pattern: try Pattern("README.markdown.extra"))).isEmpty)
    }

    private func makeTreeForCase() -> Snapshot {
        let root = Node(name: "/case", kind: .directory, size: 400, fileCount: 3)
        let names = ["README.md", "DerivedData", "Документы"]
        var children: [Node] = []
        for name in names {
            let child = Node(name: name, kind: .file, size: 100, fileCount: 1)
            child.parent = root
            children.append(child)
        }
        root.children = children
        return Snapshot(root: root, rootPath: "/case")
    }
}

extension SearchTests {

    @Test("a non-ASCII query is answered as quickly as an ASCII one")
    func nonASCIIQueryIsFast() throws {
        // Typing is per-keystroke: a query that takes seconds makes the search
        // box look frozen. Cyrillic used to take twelve seconds where the same
        // search in Latin took under one.
        let root = Node(name: "/big", kind: .directory)
        var children: [Node] = []
        for index in 0 ..< 20_000 {
            let child = Node(name: "entry-\(index)-копия", kind: .file, size: 10, fileCount: 1)
            child.parent = root
            children.append(child)
        }
        root.children = children
        root.size = 200_000
        let snapshot = Snapshot(root: root, rootPath: "/big")

        let started = Date()
        let matches = snapshot.search(Filter(pattern: try Pattern("копия")), limit: 50)
        let elapsed = Date().timeIntervalSince(started)

        #expect(matches.count == 50)
        #expect(elapsed < 1, "took \(elapsed)s")
    }

    @Test("case folding still applies to non-ASCII queries")
    func foldsNonASCIICase() throws {
        let root = Node(name: "/case", kind: .directory, size: 200, fileCount: 2)
        let upper = Node(name: "КОПИЯ.txt", kind: .file, size: 100, fileCount: 1)
        let lower = Node(name: "копия.txt", kind: .file, size: 100, fileCount: 1)
        for child in [upper, lower] { child.parent = root }
        root.children = [upper, lower]
        let snapshot = Snapshot(root: root, rootPath: "/case")

        #expect(snapshot.search(Filter(pattern: try Pattern("копия"))).count == 2)
        #expect(snapshot.search(Filter(pattern: try Pattern("КОПИЯ"))).count == 2)
    }
}
