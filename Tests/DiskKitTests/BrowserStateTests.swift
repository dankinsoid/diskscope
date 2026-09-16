import Foundation
import Testing
@testable import DiskKit

/// The browser's state lives in the CLI target, so these exercise the query
/// layer it is built on — the part that decides what a search shows.
@Suite("Browsing a snapshot")
struct BrowsingTests {

    private func makeSnapshot() -> Snapshot {
        let root = Node(name: "/work", kind: .directory)
        var children: [Node] = []
        for (name, size) in [("alpha", 3_000), ("beta", 2_000), ("gamma", 1_000)] {
            let project = Node(name: name, kind: .directory, size: Int64(size), fileCount: 1)
            let build = Node(name: ".build", kind: .directory, size: Int64(size - 100), fileCount: 1)
            build.parent = project
            project.children = [build]
            project.parent = root
            children.append(project)
        }
        root.children = children
        root.size = 6_000
        root.fileCount = 3
        return Snapshot(root: root, rootPath: "/work")
    }

    @Test("a query narrows as characters are added")
    func narrowsWhileTyping() throws {
        let snapshot = makeSnapshot()

        // Each prefix is searched in full, not just the last character typed:
        // 'a' matches every project plus their build directories, 'alpha' one.
        let matchesForA = snapshot.search(Filter(pattern: try Pattern("a")))
        let matchesForAlpha = snapshot.search(Filter(pattern: try Pattern("alpha")))

        #expect(matchesForA.count > matchesForAlpha.count)
        #expect(matchesForAlpha.map(\.name) == ["alpha"])
    }

    @Test("results are ordered largest first")
    func ordersBySize() throws {
        let snapshot = makeSnapshot()
        let matches = snapshot.searchTopmost(Filter(pattern: try Pattern(".build")))

        #expect(matches.map(\.size) == [2_900, 1_900, 900])
    }

    @Test("selecting everything a search found, then keeping one")
    func selectsAllThenExcludes() throws {
        let snapshot = makeSnapshot()
        let matches = snapshot.searchTopmost(Filter(pattern: try Pattern(".build")))

        var selection = Selection()
        for node in matches { selection.insert(node) }
        #expect(selection.totalSize(in: snapshot.root) == 5_700)

        let keep = try #require(snapshot.root.node(atPath: "/work/beta/.build"))
        selection.remove(keep)
        #expect(selection.totalSize(in: snapshot.root) == 3_800)
    }

    @Test("deleting an entry corrects every total above it")
    func detachingCorrectsAncestors() throws {
        let snapshot = makeSnapshot()
        let doomed = try #require(snapshot.root.node(atPath: "/work/alpha/.build"))
        let alpha = try #require(snapshot.root.node(atPath: "/work/alpha"))

        doomed.detachFromParent()

        #expect(alpha.children.isEmpty)
        #expect(alpha.size == 100)
        #expect(snapshot.root.size == 3_100)
        #expect(snapshot.root.node(atPath: "/work/alpha/.build") == nil)
    }
}
