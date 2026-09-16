import ArgumentParser
import Foundation

struct SkillCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "skill",
        abstract: "Install the agent skill that teaches an assistant to use dscope.",
        discussion: """
        Writes SKILL.md where coding assistants look for skills. Claude Code \
        reads ~/.claude/skills; pass --to for anywhere else, or --print to see \
        the text and place it yourself.
        """
    )

    @Option(name: .long, help: "Directory to install into, instead of the default.")
    var to: String?

    @Flag(name: .long, help: "Write the skill to stdout rather than installing it.")
    var print = false

    @Flag(name: .long, help: "Overwrite an existing installation.")
    var force = false

    func run() throws {
        let contents = Skill.contents

        if print {
            Swift.print(contents)
            return
        }

        let base = (to ?? Skill.defaultDirectory) as NSString
        let directory = URL(fileURLWithPath: base.expandingTildeInPath)
            .appendingPathComponent("diskscope")
        let file = directory.appendingPathComponent("SKILL.md")

        if FileManager.default.fileExists(atPath: file.path), !force {
            throw ValidationError("\(file.path) already exists; pass --force to replace it")
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try contents.write(to: file, atomically: true, encoding: .utf8)

        Swift.print("installed to \(file.path)")
        Swift.print("Start a new session for the assistant to pick it up.")
    }
}

enum Skill {

    /// Where Claude Code looks for user-installed skills.
    static let defaultDirectory = "~/.claude/skills"
}
