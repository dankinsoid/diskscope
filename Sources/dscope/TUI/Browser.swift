import DiskKit
import Foundation

/// The interactive browser: draws a frame, waits for a key, repeats.
final class Browser {

    private var state: BrowserState
    private let terminal = Terminal()
    private var pendingConfirmation: Confirmation?

    /// A destructive action waiting for the user to type the confirming word.
    private struct Confirmation {
        let nodes: [Node]
        let bytes: Int64
        let method: DeletionMethod
        var typed: String

        var word: String { method == .permanent ? "DELETE" : "yes" }
    }

    init(snapshot: Snapshot) {
        state = BrowserState(snapshot: snapshot)
    }

    /// Runs until the user quits. Returns paths deleted, for the caller to report.
    @discardableResult
    func run() -> [String] {
        terminal.activate()
        defer { terminal.deactivate() }

        var deleted: [String] = []

        draw()
        loop: while true {
            guard let key = terminal.readKey() else { break }

            let keys = [key]

            for key in keys {
                if pendingConfirmation != nil {
                    if let removed = handleConfirmation(key) {
                        deleted.append(contentsOf: removed)
                    }
                    continue
                }
                if state.search?.isEditing == true {
                    if handleSearchInput(key) { break loop }
                    continue
                }

                switch key {
                case .character("q"), .escape, .interrupt:
                    break loop
                default:
                    handleCommand(key)
                }
            }
            draw()
        }
        return deleted
    }

    private func draw() {
        let size = terminal.size
        state.scroll = BrowserView.scrollOffset(for: state, height: max(1, size.rows - 4))

        var lines = BrowserView.render(state, size: size)
        if let confirmation = pendingConfirmation {
            lines[lines.count - 1] = confirmationPrompt(confirmation, width: size.columns)
        }
        terminal.draw(lines)
    }

    // MARK: - Keys

    private func handleCommand(_ key: Key) {
        state.status = nil

        switch key {
        case .up, .character("k"):
            state.move(by: -1)
        case .down, .character("j"):
            state.move(by: 1)
        case .scrollUp:
            state.move(by: -3)
        case .scrollDown:
            state.move(by: 3)
        case .unknown:
            break
        case .pageUp:
            state.move(by: -(terminal.size.rows - 6))
        case .pageDown:
            state.move(by: terminal.size.rows - 6)
        case .home, .character("g"):
            state.moveTo(0)
        case .end, .character("G"):
            state.moveTo(Int.max)

        case .right, .enter, .character("l"):
            state.enter()
        case .left, .backspace, .character("h"):
            state.goUp()

        case .space:
            state.toggleSelection()
            state.move(by: 1)
        case .character("a"):
            state.selectAllRows()
        case .character("c"):
            state.clearSelection()

        case .character("/"):
            state.beginSearch(mode: .substring)
        case .character("r"):
            state.beginSearch(mode: .regex)
        case .character("s"):
            state.cycleOrder()

        case .character("d"):
            askToDelete(method: .trash)
        case .character("D"):
            askToDelete(method: .permanent)

        case .character("?"):
            state.status = "space select · a select all shown · c clear · / search · r regex · s sort · d trash · D delete"

        default:
            break
        }
    }

    /// Returns true when the browser should quit.
    private func handleSearchInput(_ key: Key) -> Bool {
        switch key {
        case .enter:
            state.commitSearch()
        case .escape:
            state.cancelSearch()
        case .interrupt:
            return true
        case .character("q") where state.search?.query.isEmpty == true:
            // An empty search box is somewhere a person can arrive by accident;
            // leaving it should not require knowing that only esc works.
            state.cancelSearch()
        case .backspace:
            state.updateSearch { $0 = String($0.dropLast()) }
        case .character(let character) where !character.isNewline:
            state.updateSearch { $0.append(character) }
        default:
            break
        }
        return false
    }

    // MARK: - Deleting

    private func askToDelete(method: DeletionMethod) {
        let nodes = state.selection.isEmpty
            ? [state.selectedNode].compactMap { $0 }
            : state.selection.nodes(in: state.snapshot.root)

        guard !nodes.isEmpty else {
            state.status = "nothing selected"
            return
        }
        pendingConfirmation = Confirmation(
            nodes: nodes,
            bytes: nodes.reduce(0) { $0 + $1.size },
            method: method,
            typed: ""
        )
    }

    /// Returns the deleted paths once the confirmation completes.
    private func handleConfirmation(_ key: Key) -> [String]? {
        guard var confirmation = pendingConfirmation else { return nil }

        switch key {
        case .escape, .interrupt:
            pendingConfirmation = nil
            state.status = "cancelled"
            return nil

        case .backspace:
            confirmation.typed = String(confirmation.typed.dropLast())
            pendingConfirmation = confirmation
            return nil

        case .character(let character):
            confirmation.typed.append(character)
            pendingConfirmation = confirmation
            return nil

        case .enter:
            guard confirmation.typed == confirmation.word else {
                pendingConfirmation = nil
                state.status = "cancelled — type \(confirmation.word) to confirm"
                return nil
            }
            pendingConfirmation = nil
            return perform(confirmation)

        default:
            return nil
        }
    }

    private func perform(_ confirmation: Confirmation) -> [String] {
        let sizes = Dictionary(
            confirmation.nodes.map { ($0.path, $0.size) }, uniquingKeysWith: { first, _ in first }
        )
        let summary = Deleter(method: confirmation.method)
            .delete(paths: confirmation.nodes.map(\.path), sizes: sizes)

        // Drop what went, so the tree on screen matches the disk.
        for outcome in summary.outcomes where outcome.succeeded {
            state.snapshot.root.node(atPath: outcome.path)?.detachFromParent()
        }
        state.selection.removeAll()
        state.reload()

        let verb = confirmation.method == .permanent ? "deleted" : "moved to Trash"
        state.status = summary.failures.isEmpty
            ? "\(verb) \(summary.deletedCount) entries, freed \(summary.freedBytes.formattedBytes())"
            : "\(verb) \(summary.deletedCount), \(summary.failures.count) failed: \(summary.failures[0].error ?? "")"

        return summary.outcomes.filter(\.succeeded).map(\.path)
    }

    private func confirmationPrompt(_ confirmation: Confirmation, width: Int) -> String {
        let action = confirmation.method == .permanent
            ? "PERMANENTLY DELETE"
            : "Move to Trash"
        let count = confirmation.nodes.count == 1 ? "1 entry" : "\(confirmation.nodes.count) entries"
        let prompt = "\(action) \(count), \(confirmation.bytes.formattedBytes())?"
            + "  type \(confirmation.word): \(confirmation.typed)▌"
        return Style.inverted(String(prompt.prefix(width)).rightPadded(to: width))
    }
}
