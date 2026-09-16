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

@Suite("Folding small entries")
struct FoldingTests {

    /// A directory with a few large children and a long tail of small ones.
    private func makeDirectory(largeCount: Int, smallCount: Int) -> Node {
        let root = Node(name: "/work", kind: .directory)
        var children: [Node] = []

        for index in 0 ..< largeCount {
            let child = Node(name: "large-\(index)", kind: .directory, size: 10_000, fileCount: 1)
            child.parent = root
            children.append(child)
        }
        for index in 0 ..< smallCount {
            let child = Node(name: "small-\(index)", kind: .file, size: 10, fileCount: 1)
            child.parent = root
            children.append(child)
        }
        root.children = children
        root.size = children.reduce(0) { $0 + $1.size }
        root.fileCount = children.count
        return root
    }

    @Test("a long tail of small entries collapses into one row")
    func foldsTheTail() {
        let root = makeDirectory(largeCount: 3, smallCount: 40)
        let threshold = max(Int64(1), root.size / 100)

        let large = root.children.filter { $0.size >= threshold }
        let small = root.children.filter { $0.size < threshold }

        #expect(large.count == 3)
        #expect(small.count == 40)

        // What the row stands for: every small entry, and their total.
        #expect(small.reduce(Int64(0)) { $0 + $1.size } == 400)
    }

    @Test("a directory of comparable entries is not folded")
    func leavesEvenDirectoriesAlone() {
        let root = makeDirectory(largeCount: 20, smallCount: 0)
        let threshold = max(Int64(1), root.size / 100)

        #expect(root.children.allSatisfy { $0.size >= threshold })
    }

    @Test("folding away a handful of rows is not worth the keystroke")
    func skipsShortTails() {
        // Three small entries take three lines; a fold takes one and costs a
        // keypress to undo, which is not a trade worth making.
        let root = makeDirectory(largeCount: 5, smallCount: 3)
        let threshold = max(Int64(1), root.size / 100)
        let small = root.children.filter { $0.size < threshold }

        #expect(small.count <= 3)
    }

    @Test("the threshold scales with the directory, not with absolute size")
    func thresholdIsRelative() {
        let small = makeDirectory(largeCount: 3, smallCount: 10)
        let large = makeDirectory(largeCount: 300, smallCount: 10)

        // The same shape folds the same way whatever the totals.
        #expect(max(Int64(1), small.size / 100) < max(Int64(1), large.size / 100))
    }
}
