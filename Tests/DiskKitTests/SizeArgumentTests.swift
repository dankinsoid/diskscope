import Testing
@testable import DiskKit

@Suite("SizeArgument")
struct SizeArgumentTests {

    @Test("parses sizes the way people write them", arguments: [
        ("0", Int64(0)),
        ("512", Int64(512)),
        ("1KB", Int64(1024)),
        ("1k", Int64(1024)),
        ("500MB", Int64(524_288_000)),
        ("1GB", Int64(1_073_741_824)),
        ("1.5GB", Int64(1_610_612_736)),
        ("2 GiB", Int64(2_147_483_648)),
        ("1tb", Int64(1_099_511_627_776)),
    ])
    func parsesSizes(_ text: String, _ expected: Int64) throws {
        let parsed = try SizeArgument.parse(text)
        #expect(parsed == expected)
    }

    @Test("rejects input that is not a size", arguments: ["", "abc", "GB", "10 parsecs"])
    func rejectsInvalidInput(_ text: String) {
        #expect(throws: SizeArgument.ParseError.self) { try SizeArgument.parse(text) }
    }
}
