import ArgumentParser

@main
struct DScope: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "dscope",
        abstract: "Find what is eating your disk space.",
        version: "0.1.0",
        subcommands: [ScanCommand.self, InfoCommand.self],
        defaultSubcommand: ScanCommand.self
    )
}
