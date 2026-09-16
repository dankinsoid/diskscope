import ArgumentParser
import Foundation

struct DoctorCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check whether this terminal can run the interactive browser."
    )

    func run() throws {
        print("TERM             \(ProcessInfo.processInfo.environment["TERM"] ?? "(unset)")")
        print("TERM_PROGRAM     \(ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "(unset)")")
        print("stdin is a tty   \(isatty(STDIN_FILENO) == 1)")
        print("stdout is a tty  \(isatty(STDOUT_FILENO) == 1)")

        guard Terminal.isInteractive else {
            print("\nNot interactive — the browser needs both stdin and stdout attached to a terminal.")
            return
        }

        let terminal = Terminal()
        terminal.activate()
        defer { terminal.deactivate() }

        terminal.draw([
            "dscope doctor",
            "",
            "Press a few keys, then q to finish.",
            "Each key you press should appear below.",
            "",
        ])

        var seen: [String] = []
        for _ in 0 ..< 12 {
            guard let key = terminal.readKey() else {
                seen.append("(input closed)")
                break
            }
            if key == .character("q") { break }
            seen.append("\(key)")
            terminal.draw(
                ["dscope doctor", "", "Press a few keys, then q to finish.", ""] + seen.map { "  \($0)" }
            )
        }
        terminal.deactivate()

        if seen.isEmpty {
            print("\nNo keys arrived — this terminal is not delivering input to the program.")
            print("The one-shot commands work regardless: dscope scan / search / top.")
        } else {
            print("\nInput works — \(seen.count) keys arrived. The browser should run here.")
        }
    }
}
