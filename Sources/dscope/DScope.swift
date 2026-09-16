import ArgumentParser
import Foundation

/// Entry point, so the bare invocation can be redirected before parsing.
@main
enum Main {

    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        if DScope.shouldBrowse(arguments) {
            arguments.insert("browse", at: 0)
        }
        DScope.main(arguments)
    }
}

struct DScope: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "dscope",
        abstract: "Find what is eating your disk space.",
        discussion: """
        Run with no arguments to explore interactively. Every command reads \
        either a directory or a snapshot saved by 'dscope scan --save', and \
        every command takes --json, so the tool is usable from scripts and \
        agents without the interactive interface.
        """,
        version: "0.1.0",
        subcommands: [
            BrowseCommand.self,
            ScanCommand.self,
            SearchCommand.self,
            TopCommand.self,
            CleanCommand.self,
            VolumesCommand.self,
            AccessCommand.self,
            UpdateCommand.self,
            InfoCommand.self,
            DoctorCommand.self,
            SkillCommand.self,
        ],
        defaultSubcommand: ScanCommand.self
    )

    /// Whether a bare invocation should open the browser.
    ///
    /// `defaultSubcommand` is resolved statically, so the choice between
    /// browsing and printing has to be made before parsing. Only an argument
    /// list that names no subcommand is rewritten, which leaves explicit
    /// commands and piped output alone.
    static func shouldBrowse(_ arguments: [String]) -> Bool {
        guard Terminal.isInteractive else { return false }

        // Listed explicitly: reading them back off `configuration` would refer
        // to the property being initialised.
        let names: Set<String> = [
            "browse", "scan", "search", "top", "clean", "volumes", "access", "update", "info", "doctor", "skill", "help",
        ]
        guard let first = arguments.first else { return true }

        // An explicit command is meant literally.
        guard !names.contains(first) else { return false }

        // Help and version print and exit; everything else — a path, or options
        // such as --snapshot — is an invitation to look around.
        let printsAndExits: Set<String> = ["-h", "--help", "--version"]
        return !printsAndExits.contains(first)
    }
}
