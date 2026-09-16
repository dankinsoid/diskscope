import Foundation
import Testing
@testable import DiskKit

@Suite("JSON output")
struct JSONOutputTests {

    private func makeSnapshot() -> Snapshot {
        let root = Node(name: "/work", kind: .directory, size: 3_000, fileCount: 2)
        let big = Node(name: "big", kind: .directory, size: 2_000, fileCount: 1)
        let leaf = Node(name: "leaf.bin", kind: .file, size: 2_000, fileCount: 1)
        let small = Node(name: "small.txt", kind: .file, size: 1_000, fileCount: 1)
        leaf.parent = big
        big.children = [leaf]
        for child in [big, small] { child.parent = root }
        root.children = [big, small]
        return Snapshot(root: root, rootPath: "/work", duration: 2)
    }

    @Test("tree output stops at the requested depth")
    func limitsDepth() throws {
        let snapshot = makeSnapshot()

        let shallow = NodeJSON.tree(snapshot.root, depth: 1)
        #expect(shallow.children?.count == 2)
        #expect(shallow.children?.first?.children == nil)

        let deep = NodeJSON.tree(snapshot.root, depth: 2)
        #expect(deep.children?.first?.children?.first?.name == "leaf.bin")
    }

    @Test("tree output drops entries below the minimum size")
    func appliesMinimumSize() {
        let tree = NodeJSON.tree(makeSnapshot().root, depth: 2, minimumSize: 1_500)
        #expect(tree.children?.map(\.name) == ["big"])
    }

    @Test("reports encode as stable JSON an agent can rely on")
    func encodesStableJSON() throws {
        let snapshot = makeSnapshot()
        let report = ScanReportJSON(snapshot: snapshot, tree: NodeJSON.tree(snapshot.root, depth: 1))
        let data = try JSONEncoder.reportEncoder(pretty: false).encode(report)
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("\"totalBytes\":3000"))
        #expect(json.contains("\"humanSize\":\"2.9 KB\""))
        #expect(json.contains("\"root\":\"/work\""))
        // Slashes stay readable and keys stay sorted, so output diffs cleanly.
        #expect(!json.contains("\\/"))
        #expect(json.firstRange(of: "\"root\"")!.lowerBound < json.firstRange(of: "\"totalBytes\"")!.lowerBound)

        let decoded = try JSONDecoder.reportDecoder().decode(ScanReportJSON.self, from: data)
        #expect(decoded.totalBytes == 3_000)
        #expect(decoded.tree?.children?.count == 2)
    }

    @Test("search reports say when results were cut off")
    func reportsTruncation() throws {
        let snapshot = makeSnapshot()
        let matches = snapshot.largest(1)
        let report = SearchReportJSON(query: "b", mode: .substring, matches: matches, truncated: true)

        #expect(report.matchCount == 1)
        #expect(report.truncated)
        #expect(report.totalBytes == matches[0].size)
    }
}

extension JSONOutputTests {

    @Test("a truncated search still reports the size of everything it matched")
    func reportsFullSizeWhenTruncated() {
        let root = Node(name: "/work", kind: .directory)
        var all: [Node] = []
        for index in 0 ..< 10 {
            let child = Node(name: "cache-\(index)", kind: .directory, size: 100, fileCount: 1)
            child.parent = root
            all.append(child)
        }
        root.children = all
        root.size = 1_000

        let listed = Array(all.prefix(3))
        let report = SearchReportJSON(
            query: "cache", mode: .substring, matches: listed, truncated: true, allMatches: all
        )

        // Summing what was printed would understate the category threefold,
        // which is exactly how a cleanup plan ends up wrong.
        #expect(report.matchCount == 3)
        #expect(report.totalMatchCount == 10)
        #expect(report.listedBytes == 300)
        #expect(report.totalBytes == 1_000)
    }

    @Test("an untruncated search reports the same figure both ways")
    func reportsOneFigureWhenComplete() {
        let node = Node(name: "only", kind: .file, size: 500, fileCount: 1)
        let report = SearchReportJSON(query: "only", mode: .substring, matches: [node], truncated: false)

        #expect(report.totalBytes == report.listedBytes)
        #expect(report.matchCount == report.totalMatchCount)
    }
}
