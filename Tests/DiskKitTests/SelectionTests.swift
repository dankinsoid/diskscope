import Foundation
import Testing
@testable import DiskKit

@Suite("Selection")
struct SelectionTests {

    /// projects/{alpha,beta,gamma}/.build plus a source file in each.
    private func makeProjects() -> Node {
        let root = Node(name: "/projects", kind: .directory)
        var children: [Node] = []
        for (name, buildSize) in [("alpha", 1_000), ("beta", 2_000), ("gamma", 4_000)] {
            let project = Node(name: name, kind: .directory, size: Int64(buildSize + 100), fileCount: 2)
            let build = Node(name: ".build", kind: .directory, size: Int64(buildSize), fileCount: 1)
            let source = Node(name: "main.swift", kind: .file, size: 100, fileCount: 1)
            for child in [build, source] { child.parent = project }
            project.children = [build, source]
            project.parent = root
            children.append(project)
        }
        root.children = children
        root.size = children.reduce(0) { $0 + $1.size }
        root.fileCount = children.reduce(0) { $0 + $1.fileCount }
        return root
    }

    @Test("selecting a directory covers everything inside it")
    func selectionCoversSubtree() {
        let root = makeProjects()
        let alpha = root.children[0]

        var selection = Selection()
        selection.insert(alpha)

        #expect(selection.covers(alpha))
        #expect(selection.covers(alpha.children[0]))
        #expect(!selection.covers(root.children[1]))
        #expect(selection.count == 1)
    }

    @Test("selecting a parent replaces its already selected children")
    func parentSubsumesChildren() {
        let root = makeProjects()
        let alpha = root.children[0]

        var selection = Selection()
        selection.insert(alpha.children[0])
        selection.insert(alpha.children[1])
        #expect(selection.count == 2)

        selection.insert(alpha)
        #expect(selection.count == 1)
        #expect(selection.totalSize(in: root) == alpha.size)
    }

    @Test("bytes freed count a selected subtree once")
    func totalDoesNotDoubleCount() {
        let root = makeProjects()
        var selection = Selection()

        selection.insert(root.children[0])
        selection.insert(root.children[0].children[0])

        #expect(selection.totalSize(in: root) == root.children[0].size)
    }

    @Test("select everything matching, then carve out one exception")
    func selectAllThenExclude() throws {
        let root = makeProjects()
        let snapshot = Snapshot(root: root, rootPath: "/projects")

        let matches = snapshot.searchTopmost(Filter(pattern: try Pattern(".build", mode: .substring)))
        #expect(matches.map(\.path) == [
            "/projects/gamma/.build",
            "/projects/beta/.build",
            "/projects/alpha/.build",
        ])

        var selection = Selection()
        for node in matches { selection.insert(node) }
        #expect(selection.totalSize(in: root) == 7_000)

        // Keep the build directory of the project still being worked on.
        let keep = try #require(root.node(atPath: "/projects/beta/.build"))
        selection.remove(keep)

        #expect(!selection.covers(keep))
        #expect(selection.covers(try #require(root.node(atPath: "/projects/alpha/.build"))))
        #expect(selection.totalSize(in: root) == 5_000)
    }

    @Test("deselecting inside a selected directory keeps its siblings selected")
    func exclusionSplitsSelectedParent() throws {
        let root = makeProjects()
        let alpha = root.children[0]

        var selection = Selection()
        selection.insert(alpha)

        // Keep the source file, drop the rest of the project.
        let source = try #require(root.node(atPath: "/projects/alpha/main.swift"))
        selection.remove(source)

        #expect(!selection.covers(source))
        #expect(selection.covers(try #require(root.node(atPath: "/projects/alpha/.build"))))
        #expect(selection.totalSize(in: root) == 1_000)
    }
}
