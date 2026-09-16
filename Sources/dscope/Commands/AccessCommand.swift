import ArgumentParser
import DiskKit
import Foundation

struct AccessCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "access",
        abstract: "Check whether this process may read the whole disk."
    )

    @OptionGroup var format: FormatOptions

    func run() throws {
        let granted = FullDiskAccess.isGranted()

        if format.json {
            try Output.emit(
                AccessReport(
                    fullDiskAccess: granted,
                    settingsURL: FullDiskAccess.settingsURL,
                    instructions: granted ? nil : FullDiskAccess.instructions
                ),
                pretty: format.pretty
            )
            return
        }

        if granted {
            print("Full Disk Access: granted")
            print("Some directories stay unreadable even so — parts of /private/var and")
            print("/System/Library are restricted by System Integrity Protection, and are")
            print("reported as unreadable rather than counted as empty.")
        } else {
            print("Full Disk Access: not granted")
            print("Parts of your home directory will be reported as empty.")
            print("")
            print(FullDiskAccess.instructions)
        }
    }
}

struct AccessReport: Codable {
    let fullDiskAccess: Bool
    let settingsURL: String
    let instructions: String?
}
