import ArgumentParser

@main
struct DScope: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "dscope",
        abstract: "Find what is eating your disk space.",
        discussion: """
        Every command reads either a directory or a snapshot saved by \
        'dscope scan --save', and every command takes --json, so the tool is \
        usable from scripts and agents without the interactive interface.
        """,
        version: "0.1.0",
        subcommands: [BrowseCommand.self, ScanCommand.self, SearchCommand.self, TopCommand.self, CleanCommand.self, VolumesCommand.self, AccessCommand.self, UpdateCommand.self, InfoCommand.self],
        defaultSubcommand: ScanCommand.self
    )
}
