import Foundation

/// How much a scan is expected to find, so progress can be a fraction.
///
/// There is no way to know the size of a tree without walking it, so the
/// estimate comes from whatever is already known: a previous scan of the same
/// path is exact enough, and otherwise the volume's used space is an upper
/// bound that at least bounds the work.
public struct ScanEstimate: Sendable {

    public let totalBytes: Int64
    public let source: Source

    public enum Source: String, Sendable {
        /// A previous scan of this path, which makes the fraction meaningful.
        case previousScan
        /// Space in use on the volume — right only when scanning a whole volume,
        /// and an over-estimate for a directory inside one.
        case volume
    }

    public init(totalBytes: Int64, source: Source) {
        self.totalBytes = totalBytes
        self.source = source
    }

    /// The best estimate available for `path`, or nil when there is none.
    ///
    /// Returning nil matters: a progress bar against a denominator that does not
    /// describe the work is worse than no bar, since it reads as fact.
    ///
    /// - Parameter previous: size a previous scan of the same path reported.
    public static func of(path: String, previous: Int64? = nil) -> ScanEstimate? {
        if let previous, previous > 0 {
            return ScanEstimate(totalBytes: previous, source: .previousScan)
        }
        guard let volume = VolumeInfo(path: path), volume.used > 0 else { return nil }

        // The volume total only describes the work when the scan covers the
        // volume; for a directory inside it the figure would be far too large.
        let standardized = (path as NSString).standardizingPath
        let isWholeVolume = standardized == volume.mountPoint || standardized == "/"
        return isWholeVolume ? ScanEstimate(totalBytes: volume.used, source: .volume) : nil
    }

    /// Fraction scanned so far, clamped so an under-estimate cannot exceed 1.
    public func fraction(scanned bytes: Int64) -> Double {
        guard totalBytes > 0 else { return 0 }
        return Swift.min(1, Double(bytes) / Double(totalBytes))
    }
}
