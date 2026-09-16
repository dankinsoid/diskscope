import ArgumentParser
import DiskKit
import Foundation

struct BrowseCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "browse",
        abstract: "Explore a scan interactively.",
        discussion: """
        Arrow keys or hjkl to move, → to enter a directory, ← to go back. \
        Space marks an entry, 'a' marks everything currently listed, '/' searches \
        the whole tree and 'r' searches by regular expression. 'd' moves what is \
        marked to the Trash, 'D' deletes it outright. '?' lists the keys.

        Marking everything a search found and then unmarking the exceptions is \
        the quickest way to clear out, say, every .build directory but one.
        """
    )

    @OptionGroup var source: SourceOptions

    @Flag(
        name: .long,
        help: "Reverse the scroll wheel, if it moves the list the wrong way."
    )
    var naturalScroll = false

    /// Keeps the parting summary to a handful of lines.
    private func summaryThreshold(for snapshot: Snapshot) -> Int64 {
        max(1_048_576, snapshot.totalSize / 50)
    }

    func validate() throws {
        guard Terminal.isInteractive else {
            throw ValidationError("browse needs a terminal; use 'scan' or 'search' when piping output")
        }
    }

    func run() throws {
        // Said before the wait, not after: a scan of a whole disk takes minutes,
        // and the time to learn it could have been saved is before spending it.
        if source.snapshot == nil, Terminal.isInteractive {
            Output.note(
                "scanning \(source.path) — to keep the result, run"
                    + " 'dscope scan \(source.path) --save <file>' and browse that with --snapshot"
            )
        }

        let snapshot = try source.load(summary: false)
        let deleted = Browser(snapshot: snapshot, invertScroll: naturalScroll).run()

        // The browser draws on the alternate screen, which is restored on exit —
        // without this the terminal looks as though nothing ever ran.
        print(TreeRenderer.render(snapshot.root, depth: 1, minimumSize: summaryThreshold(for: snapshot)))
        if deleted.isEmpty {
            Output.note("save this scan with: dscope scan \(snapshot.rootPath) --save <file>")
        }

        // Printed after leaving the alternate screen, so it survives on screen.
        if !deleted.isEmpty {
            print("removed \(deleted.count) entries:")
            for path in deleted.prefix(20) {
                print("  \(path)")
            }
            if deleted.count > 20 {
                print("  … and \(deleted.count - 20) more")
            }
        }
    }
}
