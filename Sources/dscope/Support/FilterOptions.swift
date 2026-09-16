import ArgumentParser
import DiskKit
import Foundation

/// Predicates shared by every command that selects entries.
///
/// One set rather than per-command flags: the useful questions combine them —
/// "build directories over 500MB untouched for six months" is a name, a size
/// and an age at once, and until now each lived on a different command.
struct FilterOptions: ParsableArguments {

    @Option(
        name: [.customShort("n"), .long],
        help: ArgumentHelp(
            "Match entries by name.",
            discussion: "Substring by default; see --glob and --regex.",
            valueName: "pattern"
        )
    )
    var name: String?

    @Flag(name: .long, help: "Treat the pattern as a shell glob, anchored to the whole name.")
    var glob = false

    @Flag(name: .long, help: "Treat the pattern as a regular expression.")
    var regex = false

    @Flag(name: .long, help: "Match against the full path rather than the name.")
    var path = false

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Match entries by size.",
            discussion: "'+1GB' at least, '-100MB' at most, '500MB' at least. Repeat to bound both ends.",
            valueName: "bound"
        )
    )
    var size: [String] = []

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Match by when the entry was last read.",
            discussion: "'+6m' untouched for six months, '-7d' used within a week. Units: h d w m y.",
            valueName: "age"
        )
    )
    var accessed: [String] = []

    @Option(
        name: .long,
        help: ArgumentHelp("Match by when the entry was last written.", valueName: "age")
    )
    var modified: [String] = []

    @Flag(name: .long, help: "Match files only.")
    var filesOnly = false

    @Flag(name: .long, help: "Match directories only.")
    var dirsOnly = false

    @Flag(name: .long, help: "Match only entries that could not be read.")
    var unreadable = false

    func validate() throws {
        if glob, regex {
            throw ValidationError("--glob and --regex are alternatives; pick one")
        }
        if filesOnly, dirsOnly {
            throw ValidationError("--files-only and --dirs-only exclude each other")
        }
        // Whether a pattern was given cannot be judged here: a command may take
        // one positionally, and only it knows.
    }

    var mode: MatchMode {
        if glob { return .glob }
        if regex { return .regex }
        return .substring
    }

    /// Builds the filter, or nil when no predicate was given.
    func build(defaultPattern: String? = nil) throws -> Filter {
        let text = name ?? defaultPattern
        let pattern = try text.map { try Pattern($0, mode: mode, matchesFullPath: path) }

        var kinds: Set<Node.Kind>?
        if filesOnly { kinds = [.file, .symlink] }
        if dirsOnly { kinds = [.directory] }

        return Filter(
            pattern: pattern,
            size: try Self.combine(size, SizeBound.init(parsing:)),
            kinds: kinds,
            accessed: try Self.combine(accessed) { try AgeBound(parsing: $0) },
            modified: try Self.combine(modified) { try AgeBound(parsing: $0) },
            unreadableOnly: unreadable
        )
    }

    /// Merges repeated bounds, so `--size +1GB --size -5GB` is a range.
    private static func combine(_ values: [String], _ parse: (String) throws -> SizeBound) throws -> SizeBound {
        try values.reduce(into: SizeBound()) { result, text in
            let bound = try parse(text)
            result = SizeBound(
                minimum: bound.minimum ?? result.minimum,
                maximum: bound.maximum ?? result.maximum
            )
        }
    }

    private static func combine(_ values: [String], _ parse: (String) throws -> AgeBound) throws -> AgeBound {
        try values.reduce(into: AgeBound()) { result, text in
            let bound = try parse(text)
            result = AgeBound(
                before: bound.before ?? result.before,
                after: bound.after ?? result.after
            )
        }
    }
}
