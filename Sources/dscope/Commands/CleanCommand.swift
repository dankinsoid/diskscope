import ArgumentParser
import DiskKit
import Foundation

struct CleanCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Delete everything matching a pattern.",
        discussion: """
        Shows what would be deleted and stops. Pass --apply to actually delete, \
        and --except to keep specific matches:

          dscope clean '.build' ~/Code --except tabby-app-ios --apply

        Deletion moves items to the Trash unless --permanent is given.
        """
    )

    @Argument(help: "Text, glob or regular expression to match.")
    var query: String

    @OptionGroup var source: SourceOptions
    @OptionGroup var filter: FilterOptions
    @OptionGroup var format: FormatOptions

    @Option(name: .shortAndLong, help: "Match as substring, glob or regex.")
    var mode: MatchMode = .substring

    @Option(name: .long, parsing: .upToNextOption, help: "Keep matches whose path contains any of these.")
    var except: [String] = []

    @Option(name: .long, help: "Ignore matches smaller than this.")
    var min = "0"

    @Flag(name: .long, help: "Actually delete. Without this, nothing is touched.")
    var apply = false

    @Flag(name: .long, help: "Delete outright instead of moving to the Trash.")
    var permanent = false

    @Flag(name: .long, help: "Skip the confirmation prompt. Requires --apply.")
    var yes = false

    func validate() throws {
        if yes, !apply {
            throw ValidationError("--yes only makes sense together with --apply")
        }
        if permanent, !apply {
            throw ValidationError("--permanent only makes sense together with --apply")
        }
    }

    func run() throws {
        let snapshot = try source.load(quiet: format.json)
        var conditions = try filter.build(defaultPattern: query)
        conditions.pattern = try Pattern(query, mode: mode)
        if conditions.size.isEmpty {
            conditions.size = SizeBound(minimum: try SizeArgument.parse(min))
        }

        let matches = snapshot.searchTopmost(conditions, sortedBy: .size)
        let kept = matches.filter { node in except.contains { node.path.contains($0) } }
        let doomed = matches.filter { node in !except.contains { node.path.contains($0) } }

        var selection = Selection()
        for node in doomed { selection.insert(node) }

        let deleter = Deleter(method: permanent ? .permanent : .trash)
        let total = selection.totalSize(in: snapshot.root)

        guard !doomed.isEmpty else {
            if format.json {
                try Output.emit(CleanReport(applied: false, matches: [], kept: kept.map(\.path), freedBytes: 0), pretty: format.pretty)
            } else {
                Output.note("nothing matches '\(query)'")
            }
            return
        }

        if !apply {
            if format.json {
                try Output.emit(
                    CleanReport(
                        applied: false,
                        matches: doomed.map { PlannedDeletion($0, refusal: deleter.check($0.path)) },
                        kept: kept.map(\.path),
                        freedBytes: total
                    ),
                    pretty: format.pretty
                )
                return
            }
            for node in doomed {
                let refusal = deleter.check(node.path).map { "  \($0)" } ?? ""
                print("\(node.size.formattedBytes())\t\(node.path)\(refusal)")
            }
            for node in kept {
                print("kept    \t\(node.path)")
            }
            Output.note("would free \(total.formattedBytes()) from \(doomed.count) entries — re-run with --apply")
            return
        }

        if !yes, !format.json {
            let destination = permanent ? "PERMANENTLY DELETE" : "move to Trash"
            print("About to \(destination) \(doomed.count) entries, freeing \(total.formattedBytes()).")
            print("Type 'yes' to continue: ", terminator: "")
            guard readLine()?.trimmingCharacters(in: .whitespaces).lowercased() == "yes" else {
                Output.note("cancelled")
                throw ExitCode(1)
            }
        } else if !yes, format.json {
            throw ValidationError("--json with --apply requires --yes, since there is nobody to confirm")
        }

        let sizes = Dictionary(uniqueKeysWithValues: doomed.map { ($0.path, $0.size) })
        let summary = deleter.delete(paths: doomed.map(\.path), sizes: sizes)

        if format.json {
            try Output.emit(
                CleanReport(
                    applied: true,
                    matches: summary.outcomes.map { PlannedDeletion(path: $0.path, bytes: $0.bytes, refusal: $0.error) },
                    kept: kept.map(\.path),
                    freedBytes: summary.freedBytes
                ),
                pretty: format.pretty
            )
            return
        }

        Output.note("freed \(summary.freedBytes.formattedBytes()) from \(summary.deletedCount) entries")
        for failure in summary.failures {
            Output.note("failed: \(failure.path) — \(failure.error ?? "unknown error")")
        }
        if !summary.failures.isEmpty { throw ExitCode(1) }
    }
}

struct PlannedDeletion: Codable {
    let path: String
    let bytes: Int64
    let humanSize: String
    let refusal: String?

    init(_ node: Node, refusal: DeletionRefusal?) {
        self.path = node.path
        self.bytes = node.size
        self.humanSize = node.size.formattedBytes()
        self.refusal = refusal?.description
    }

    init(path: String, bytes: Int64, refusal: String?) {
        self.path = path
        self.bytes = bytes
        self.humanSize = bytes.formattedBytes()
        self.refusal = refusal
    }
}

struct CleanReport: Codable {
    let applied: Bool
    let matches: [PlannedDeletion]
    let kept: [String]
    let freedBytes: Int64
    let humanSize: String

    init(applied: Bool, matches: [PlannedDeletion], kept: [String], freedBytes: Int64) {
        self.applied = applied
        self.matches = matches
        self.kept = kept
        self.freedBytes = freedBytes
        self.humanSize = freedBytes.formattedBytes()
    }
}
