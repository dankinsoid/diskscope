import Foundation

/// A size constraint written the way `find` and `fd` accept them: `+1GB` for at
/// least, `-100MB` for at most, a bare size for at least.
public struct SizeBound: Sendable, Equatable {

    public let minimum: Int64?
    public let maximum: Int64?

    public init(minimum: Int64? = nil, maximum: Int64? = nil) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public init(parsing text: String) throws {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { throw SizeArgument.ParseError.invalid(text) }

        // A leading '-' is indistinguishable from a flag on the command line, so
        // the same bound can be written in words.
        if trimmed.lowercased().hasPrefix("under") {
            trimmed = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            self.init(maximum: try SizeArgument.parse(trimmed))
            return
        }
        if trimmed.lowercased().hasPrefix("over") {
            trimmed = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            self.init(minimum: try SizeArgument.parse(trimmed))
            return
        }

        switch first {
        case "+":
            self.init(minimum: try SizeArgument.parse(String(trimmed.dropFirst())))
        case "-":
            self.init(maximum: try SizeArgument.parse(String(trimmed.dropFirst())))
        default:
            // A bare size reads as a floor, which is what anyone hunting for
            // large things means by it.
            self.init(minimum: try SizeArgument.parse(trimmed))
        }
    }

    public func contains(_ size: Int64) -> Bool {
        if let minimum, size < minimum { return false }
        if let maximum, size > maximum { return false }
        return true
    }

    public var isEmpty: Bool { minimum == nil && maximum == nil }
}

/// An age constraint: `+30d` for older than, `-7d` for newer than.
///
/// Units follow `find`: `d` days, `w` weeks, `m` months, `y` years. Hours are
/// spelled `h`, since a scan is often minutes old.
public struct AgeBound: Sendable, Equatable {

    /// Nothing touched more recently than this date.
    public let before: Date?

    /// Nothing touched longer ago than this date.
    public let after: Date?

    public init(before: Date? = nil, after: Date? = nil) {
        self.before = before
        self.after = after
    }

    public init(parsing text: String, now: Date = Date()) throws {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { throw AgeError.invalid(text) }

        // '-7d' looks like a flag to an argument parser; 'within 7d' does not.
        if trimmed.lowercased().hasPrefix("within") {
            trimmed = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            self.init(after: now.addingTimeInterval(-(try Self.seconds(trimmed))))
            return
        }
        if trimmed.lowercased().hasPrefix("over") {
            trimmed = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            self.init(before: now.addingTimeInterval(-(try Self.seconds(trimmed))))
            return
        }

        switch first {
        case "+":
            // Older than: last touched before that cutoff.
            self.init(before: now.addingTimeInterval(-(try Self.seconds(String(trimmed.dropFirst())))))
        case "-":
            self.init(after: now.addingTimeInterval(-(try Self.seconds(String(trimmed.dropFirst())))))
        default:
            self.init(before: now.addingTimeInterval(-(try Self.seconds(trimmed))))
        }
    }

    public func contains(_ date: Date?) -> Bool {
        guard let date else { return before == nil && after == nil }
        if let before, date >= before { return false }
        if let after, date < after { return false }
        return true
    }

    public var isEmpty: Bool { before == nil && after == nil }

    private static func seconds(_ text: String) throws -> TimeInterval {
        let digits = text.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(digits), value >= 0 else { throw AgeError.invalid(text) }

        let unit = text.dropFirst(digits.count).trimmingCharacters(in: .whitespaces).lowercased()
        let multiplier: Double = switch unit {
        case "h": 3_600
        case "", "d": 86_400
        case "w": 604_800
        case "m": 2_592_000  // 30 days
        case "y": 31_536_000
        default: throw AgeError.unknownUnit(unit)
        }
        return value * multiplier
    }

    public enum AgeError: Error, CustomStringConvertible {
        case invalid(String)
        case unknownUnit(String)

        public var description: String {
            switch self {
            case .invalid(let text): "'\(text)' is not an age — try 30d, +6m, -1w"
            case .unknownUnit(let unit): "unknown time unit '\(unit)' — use h, d, w, m or y"
            }
        }
    }
}
