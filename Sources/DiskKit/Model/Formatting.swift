import Foundation

public enum ByteFormat: Sendable {
    /// Powers of 1024, the unit Finder and `du` report for allocated blocks.
    case binary
    case exact
}

public extension Int64 {

    /// Human-readable size, three significant digits wide.
    func formattedBytes(_ format: ByteFormat = .binary) -> String {
        switch format {
        case .exact:
            return String(self)
        case .binary:
            let units = ["B", "KB", "MB", "GB", "TB", "PB"]
            var value = Double(self)
            var unit = 0
            while value >= 1024, unit < units.count - 1 {
                value /= 1024
                unit += 1
            }
            if unit == 0 { return "\(self) B" }
            return String(format: value >= 100 ? "%.0f %@" : "%.1f %@", value, units[unit])
        }
    }
}

public extension Date {

    /// Coarse age, enough to spot something untouched for years.
    var relativeAge: String {
        let days = Int(-timeIntervalSinceNow / 86_400)
        switch days {
        case ..<0: return "in the future"
        case 0: return "today"
        case 1: return "yesterday"
        case 2 ..< 30: return "\(days)d ago"
        case 30 ..< 365: return "\(days / 30)mo ago"
        default:
            let years = days / 365
            return years == 1 ? "1y ago" : "\(years)y ago"
        }
    }
}
