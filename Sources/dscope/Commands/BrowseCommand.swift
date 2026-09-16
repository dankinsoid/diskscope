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

    func validate() throws {
        guard Terminal.isInteractive else {
            throw ValidationError("browse needs a terminal; use 'scan' or 'search' when piping output")
        }
    }

    func run() throws {
        let snapshot = try source.load()
        let deleted = Browser(snapshot: snapshot).run()

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
