import Foundation
import Testing
@testable import DiskKit

@Suite("SizeBound")
struct SizeBoundTests {

    @Test("reads find-style bounds", arguments: [
        "+1GB:1073741824:-",
        "+500MB:524288000:-",
        "-100MB:-:104857600",
        "2GB:2147483648:-",
        "+0:0:-",
    ])
    func parsesBounds(_ spec: String) throws {
        // Encoded as text because a tuple of optionals confuses the argument
        // literal's type inference.
        let parts = spec.split(separator: ":").map(String.init)
        let bound = try SizeBound(parsing: parts[0])

        #expect(bound.minimum == (parts[1] == "-" ? nil : Int64(parts[1])))
        #expect(bound.maximum == (parts[2] == "-" ? nil : Int64(parts[2])))
    }

    @Test("a bare size is a floor, which is what people mean by it")
    func bareSizeIsMinimum() throws {
        let bound = try SizeBound(parsing: "1GB")

        #expect(bound.contains(2_000_000_000))
        #expect(!bound.contains(500_000_000))
    }

    @Test("bounds combine into a range")
    func formsRange() {
        let bound = SizeBound(minimum: 1_000, maximum: 5_000)

        #expect(!bound.contains(999))
        #expect(bound.contains(1_000))
        #expect(bound.contains(5_000))
        #expect(!bound.contains(5_001))
    }

    @Test("an empty bound admits everything")
    func emptyAdmitsAll() {
        let bound = SizeBound()

        #expect(bound.isEmpty)
        #expect(bound.contains(0))
        #expect(bound.contains(.max))
    }

    @Test("accepts word forms, since a leading dash reads as a flag")
    func parsesWordForms() throws {
        let atMost = try SizeBound(parsing: "under 1GB")
        #expect(atMost.maximum == 1_073_741_824)
        #expect(atMost.minimum == nil)

        let atLeast = try SizeBound(parsing: "over 500MB")
        #expect(atLeast.minimum == 524_288_000)
        #expect(atLeast.maximum == nil)

        #expect(try SizeBound(parsing: "UNDER 2GB").maximum == 2_147_483_648)
    }

    @Test("rejects what is not a size", arguments: ["+", "-", "abc", "+10 parsecs"])
    func rejectsGarbage(_ text: String) {
        #expect(throws: (any Error).self) { try SizeBound(parsing: text) }
    }
}

@Suite("AgeBound")
struct AgeBoundTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("'+6m' means untouched for six months")
    func parsesOlderThan() throws {
        let bound = try AgeBound(parsing: "+6m", now: now)

        let lastYear = now.addingTimeInterval(-365 * 86_400)
        let lastWeek = now.addingTimeInterval(-7 * 86_400)

        #expect(bound.contains(lastYear))
        #expect(!bound.contains(lastWeek))
    }

    @Test("'-7d' means used within the last week")
    func parsesNewerThan() throws {
        let bound = try AgeBound(parsing: "-7d", now: now)

        #expect(bound.contains(now.addingTimeInterval(-86_400)))
        #expect(!bound.contains(now.addingTimeInterval(-30 * 86_400)))
    }

    @Test("units follow find", arguments: [
        ("1h", 3_600.0), ("1d", 86_400.0), ("1w", 604_800.0),
        ("1m", 2_592_000.0), ("1y", 31_536_000.0), ("30", 2_592_000.0),
    ])
    func parsesUnits(_ text: String, _ seconds: Double) throws {
        let bound = try AgeBound(parsing: text, now: now)
        let cutoff = try #require(bound.before)

        #expect(abs(cutoff.timeIntervalSince(now) + seconds) < 1)
    }

    @Test("an entry with no recorded date fails a date condition")
    func rejectsMissingDates() throws {
        // Reporting something as stale when its date is unknown would be a
        // guess dressed as a fact.
        let bound = try AgeBound(parsing: "+1y", now: now)
        #expect(!bound.contains(nil))
        #expect(AgeBound().contains(nil))
    }

    @Test("accepts word forms for ages too")
    func parsesWordForms() throws {
        let recent = try AgeBound(parsing: "within 7d", now: now)
        #expect(recent.contains(now.addingTimeInterval(-86_400)))
        #expect(!recent.contains(now.addingTimeInterval(-30 * 86_400)))

        let stale = try AgeBound(parsing: "over 6m", now: now)
        #expect(stale.contains(now.addingTimeInterval(-365 * 86_400)))
        #expect(!stale.contains(now.addingTimeInterval(-86_400)))
    }

    @Test("rejects what is not an age", arguments: ["", "soon", "5 fortnights", "+x"])
    func rejectsGarbage(_ text: String) {
        #expect(throws: (any Error).self) { try AgeBound(parsing: text, now: now) }
    }
}

@Suite("Combined conditions")
struct CombinedFilterTests {

    private func makeSnapshot() -> Snapshot {
        let root = Node(name: "/work", kind: .directory, size: 10_000, fileCount: 3)
        let recent = Node(
            name: "recent.build", kind: .directory, size: 5_000, fileCount: 1,
            modified: Date(timeIntervalSince1970: 1_699_000_000),
            accessed: Date(timeIntervalSince1970: 1_699_900_000)
        )
        let old = Node(
            name: "old.build", kind: .directory, size: 4_000, fileCount: 1,
            modified: Date(timeIntervalSince1970: 1_600_000_000),
            accessed: Date(timeIntervalSince1970: 1_600_000_000)
        )
        let small = Node(
            name: "tiny.build", kind: .file, size: 100, fileCount: 1,
            modified: Date(timeIntervalSince1970: 1_600_000_000),
            accessed: Date(timeIntervalSince1970: 1_600_000_000)
        )
        for child in [recent, old, small] { child.parent = root }
        root.children = [recent, old, small]
        return Snapshot(root: root, rootPath: "/work")
    }

    @Test("name, size and age narrow together")
    func conditionsCombine() throws {
        let snapshot = makeSnapshot()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let byName = Filter(pattern: try Pattern(".build"))
        #expect(snapshot.search(byName).count == 3)

        var withSize = byName
        withSize.size = SizeBound(minimum: 1_000)
        #expect(snapshot.search(withSize).count == 2)

        var withAge = withSize
        withAge.accessed = try AgeBound(parsing: "+6m", now: now)
        #expect(snapshot.search(withAge).map(\.name) == ["old.build"])
    }

    @Test("kind narrows to files or directories")
    func filtersByKind() throws {
        let snapshot = makeSnapshot()

        #expect(snapshot.search(Filter(kinds: [.file])).map(\.name) == ["tiny.build"])
        #expect(snapshot.search(Filter(kinds: [.directory])).count == 2)
    }

    @Test("a size range excludes both ends")
    func filtersBySizeRange() {
        let snapshot = makeSnapshot()
        let filter = Filter(size: SizeBound(minimum: 1_000, maximum: 4_500))

        #expect(snapshot.search(filter).map(\.name) == ["old.build"])
    }
}
