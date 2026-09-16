import Foundation
import Testing
@testable import DiskKit

@Suite("Formatting")
struct FormattingTests {

    @Test("sizes read the way du and Finder report them", arguments: [
        (Int64(0), "0 B"),
        (512, "512 B"),
        (1024, "1.0 KB"),
        (1_048_576, "1.0 MB"),
        (1_610_612_736, "1.5 GB"),
        (107_374_182_400, "100 GB"),
    ])
    func formatsBytes(_ value: Int64, _ expected: String) {
        #expect(value.formattedBytes() == expected)
    }

    @Test("exact format stays machine-readable")
    func formatsExactBytes() {
        #expect(Int64(1_048_576).formattedBytes(.exact) == "1048576")
    }

    @Test("ages are coarse enough to spot something long forgotten")
    func formatsAges() {
        #expect(Date().relativeAge == "today")
        #expect(Date(timeIntervalSinceNow: -86_400).relativeAge == "yesterday")
        #expect(Date(timeIntervalSinceNow: -5 * 86_400).relativeAge == "5d ago")
        #expect(Date(timeIntervalSinceNow: -70 * 86_400).relativeAge == "2mo ago")
        #expect(Date(timeIntervalSinceNow: -400 * 86_400).relativeAge == "1y ago")
        #expect(Date(timeIntervalSinceNow: -900 * 86_400).relativeAge == "2y ago")
    }
}
