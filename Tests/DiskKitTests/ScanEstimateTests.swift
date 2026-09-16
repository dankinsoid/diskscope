import Foundation
import Testing
@testable import DiskKit

@Suite("ScanEstimate")
struct ScanEstimateTests {

    @Test("prefers a previous scan of the same path")
    func prefersPreviousScan() throws {
        let estimate = try #require(ScanEstimate.of(path: "/", previous: 387_000_000_000))

        #expect(estimate.source == .previousScan)
        #expect(estimate.totalBytes == 387_000_000_000)
    }

    @Test("falls back to the volume when scanning a whole volume")
    func usesVolumeForWholeVolumeScan() throws {
        let estimate = try #require(ScanEstimate.of(path: "/"))

        #expect(estimate.source == .volume)
        #expect(estimate.totalBytes > 0)
    }

    @Test("offers no estimate for a directory inside a volume")
    func declinesForSubdirectory() {
        // The volume total says nothing about one directory in it, and a
        // progress bar against it would read as fact while being wrong.
        #expect(ScanEstimate.of(path: NSHomeDirectory()) == nil)
        #expect(ScanEstimate.of(path: "/usr/share") == nil)
    }

    @Test("a previous scan beats the volume even for a subdirectory")
    func previousScanWinsForSubdirectory() throws {
        let estimate = try #require(ScanEstimate.of(path: NSHomeDirectory(), previous: 60_000_000_000))

        #expect(estimate.source == .previousScan)
        #expect(estimate.totalBytes == 60_000_000_000)
    }

    @Test("fraction never exceeds one when the tree outgrew the estimate")
    func clampsOverrun() {
        let estimate = ScanEstimate(totalBytes: 1_000, source: .previousScan)

        #expect(estimate.fraction(scanned: 0) == 0)
        #expect(estimate.fraction(scanned: 500) == 0.5)
        #expect(estimate.fraction(scanned: 5_000) == 1)
    }

    @Test("an empty estimate reports no progress rather than dividing by zero")
    func handlesZeroTotal() {
        #expect(ScanEstimate(totalBytes: 0, source: .volume).fraction(scanned: 100) == 0)
    }
}
