import Foundation

/// Parses sizes written the way people say them: `1GB`, `500m`, `2.5 GiB`.
public enum SizeArgument {

    public static func parse(_ text: String) throws -> Int64 {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { throw ParseError.invalid(text) }

        let digits = trimmed.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(digits) else { throw ParseError.invalid(text) }

        let unit = trimmed.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        let multiplier: Double = switch unit {
        case "", "b": 1
        case "k", "kb", "kib": 1024
        case "m", "mb", "mib": 1024 * 1024
        case "g", "gb", "gib": 1024 * 1024 * 1024
        case "t", "tb", "tib": 1024 * 1024 * 1024 * 1024
        default: throw ParseError.unknownUnit(unit)
        }
        return Int64(value * multiplier)
    }

    public enum ParseError: Error, CustomStringConvertible {
        case invalid(String)
        case unknownUnit(String)

        public var description: String {
            switch self {
            case .invalid(let text): "'\(text)' is not a size"
            case .unknownUnit(let unit): "unknown size unit '\(unit)' — use B, KB, MB, GB or TB"
            }
        }
    }
}
