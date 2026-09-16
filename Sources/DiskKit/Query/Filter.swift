import Foundation

/// How a text pattern is matched against a node.
public enum MatchMode: String, Sendable, CaseIterable {
    /// Case-insensitive substring match on the node name.
    case substring
    /// Shell-style wildcards (`*`, `?`) anchored to the whole name.
    case glob
    case regex
}

/// A compiled text pattern, reused across every node of a snapshot.
public struct Pattern: Sendable {

    public let text: String
    public let mode: MatchMode
    public let matchesFullPath: Bool
    /// `NSRegularExpression` is safe to match from several threads at once,
    /// which `Regex` is not; searching a snapshot fans out across cores.
    private let regex: NSRegularExpression?

    public init(_ text: String, mode: MatchMode = .substring, matchesFullPath: Bool = false) throws {
        self.text = text
        self.mode = mode
        self.matchesFullPath = matchesFullPath

        switch mode {
        case .substring:
            regex = nil
        case .glob:
            regex = try NSRegularExpression(pattern: Pattern.globToRegex(text), options: [.caseInsensitive])
        case .regex:
            regex = try NSRegularExpression(pattern: text, options: [.caseInsensitive])
        }
    }

    public func matches(_ node: Node) -> Bool {
        let subject = matchesFullPath ? node.path : node.name
        switch mode {
        case .substring:
            return subject.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        case .glob, .regex:
            guard let regex else { return false }
            let range = NSRange(subject.startIndex ..< subject.endIndex, in: subject)
            return regex.firstMatch(in: subject, options: [], range: range) != nil
        }
    }

    /// Translates `*` and `?` into an anchored regular expression.
    private static func globToRegex(_ glob: String) -> String {
        var pattern = "^"
        for character in glob {
            switch character {
            case "*": pattern += ".*"
            case "?": pattern += "."
            default: pattern += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        return pattern + "$"
    }
}

/// Narrows a snapshot down to the nodes worth looking at.
public struct Filter: Sendable {

    public var pattern: Pattern?
    public var minimumSize: Int64?
    public var kinds: Set<Node.Kind>?

    /// Keep only entries not accessed since this date.
    public var notAccessedSince: Date?

    /// Keep only entries whose subtree could not be fully read.
    public var unreadableOnly: Bool

    public init(
        pattern: Pattern? = nil,
        minimumSize: Int64? = nil,
        kinds: Set<Node.Kind>? = nil,
        notAccessedSince: Date? = nil,
        unreadableOnly: Bool = false
    ) {
        self.pattern = pattern
        self.minimumSize = minimumSize
        self.kinds = kinds
        self.notAccessedSince = notAccessedSince
        self.unreadableOnly = unreadableOnly
    }

    public var isEmpty: Bool {
        pattern == nil && minimumSize == nil && kinds == nil
            && notAccessedSince == nil && !unreadableOnly
    }

    public func matches(_ node: Node) -> Bool {
        if let minimumSize, node.size < minimumSize { return false }
        if let kinds, !kinds.contains(node.kind) { return false }
        if unreadableOnly, node.error == nil { return false }
        if let notAccessedSince {
            guard let accessed = node.accessed, accessed < notAccessedSince else { return false }
        }
        if let pattern, !pattern.matches(node) { return false }
        return true
    }
}

public enum NodeOrder: String, Sendable, CaseIterable {
    case size
    case name
    case files
    case modified
    case accessed

    public func compare(_ first: Node, _ second: Node) -> Bool {
        switch self {
        case .size: first.size > second.size
        case .files: first.fileCount > second.fileCount
        case .name: first.name.localizedStandardCompare(second.name) == .orderedAscending
        case .modified: (first.modified ?? .distantPast) > (second.modified ?? .distantPast)
        case .accessed: (first.accessed ?? .distantPast) > (second.accessed ?? .distantPast)
        }
    }
}
