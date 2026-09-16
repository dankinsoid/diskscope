import Foundation

/// Raw-mode terminal control: keys arrive unbuffered, output is drawn in place.
final class Terminal {

    private var original = termios()
    private(set) var isActive = false

    /// The terminal to restore if the process is killed mid-session.
    ///
    /// A signal bypasses `defer`, so without this a Ctrl-C leaves the terminal
    /// in raw mode with no cursor and the alternate screen still showing.
    private nonisolated(unsafe) static var active: Terminal?

    var size: (rows: Int, columns: Int) {
        var window = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &window) == 0, window.ws_row > 0 else {
            return (24, 80)
        }
        return (Int(window.ws_row), Int(window.ws_col))
    }

    static var isInteractive: Bool {
        isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    }

    func activate() {
        guard !isActive else { return }
        tcgetattr(STDIN_FILENO, &original)

        var raw = original
        // Disable line buffering and echo so keys arrive as they are pressed.
        //
        // ISIG stays on deliberately: if anything about the terminal keeps this
        // program from reading input, Ctrl-C must still kill it. Handling that
        // byte ourselves would leave no way out of a session that is not
        // responding.
        raw.c_lflag &= ~(UInt(ECHO) | UInt(ICANON) | UInt(IEXTEN))
        raw.c_iflag &= ~(UInt(IXON) | UInt(ICRNL))
        raw.c_oflag &= ~UInt(OPOST)
        // c_cc is a tuple; taking a pointer to the whole struct keeps the write
        // aimed at `raw` itself, where a pointer to the field alone would land
        // in a temporary copy and be discarded.
        withUnsafeMutablePointer(to: &raw) { pointer in
            let controls = UnsafeMutableRawPointer(pointer)
                .advanced(by: MemoryLayout<termios>.offset(of: \.c_cc)!)
                .assumingMemoryBound(to: cc_t.self)
            controls[Int(VMIN)] = 1
            controls[Int(VTIME)] = 0
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)

        write("\u{1B}[?1049h")  // Alternate screen, so the shell scrollback survives.
        write("\u{1B}[?25l")
        // Ask for wheel events in SGR form. Without this the terminal scrolls
        // its own buffer, which on the alternate screen does nothing at all.
        write("\u{1B}[?1000h\u{1B}[?1006h")
        isActive = true

        Terminal.active = self
        Terminal.installSignalHandlers()
    }

    /// Restores the terminal when a signal would otherwise skip the cleanup.
    private static func installSignalHandlers() {
        for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
            signal(signalNumber) { number in
                Terminal.active?.deactivate()
                signal(number, SIG_DFL)
                raise(number)
            }
        }
    }

    func deactivate() {
        guard isActive else { return }
        Terminal.active = nil
        write("\u{1B}[?1006l\u{1B}[?1000l")
        write("\u{1B}[?25h")
        write("\u{1B}[?1049l")
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        isActive = false
    }

    func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    /// Draws a whole frame, replacing what was on screen.
    func draw(_ lines: [String]) {
        var output = "\u{1B}[H"  // Home, then clear each line as it is written.

        for (index, line) in lines.enumerated() {
            output += "\u{1B}[2K" + line
            // No newline after the last line: writing one on the bottom row
            // scrolls the terminal, carrying the top line — the header, and the
            // search field with it — off the screen.
            if index < lines.count - 1 {
                output += "\r\n"
            }
        }
        output += "\u{1B}[J"  // Erase anything left below a shorter frame.
        write(output)
    }

    /// Whether more input is already waiting, so a burst can be drained before
    /// redrawing. Typing arrives faster than a search over a large tree can run.
    func hasPendingInput() -> Bool {
        waitForInput(timeout: 0)
    }

    /// Waits up to `timeout` seconds for a byte to become readable.
    func waitForInput(timeout: TimeInterval) -> Bool {
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        return poll(&descriptor, 1, Int32(timeout * 1000)) > 0
    }

    /// A byte read while completing a sequence that turned out to start the
    /// next keystroke; consumed before touching the terminal again.
    private var pushedBack: UInt8?

    /// Blocks until a key is pressed.
    func readKey() -> Key? {
        var byte: UInt8 = 0
        if let pending = pushedBack {
            pushedBack = nil
            byte = pending
        } else {
            guard read(STDIN_FILENO, &byte, 1) == 1 else { return nil }
        }

        switch byte {
        case 0x1B:
            return readEscapeSequence()
        case 0x0D, 0x0A:
            return .enter
        case 0x7F, 0x08:
            return .backspace
        case 0x03:
            return .interrupt
        case 0x20:
            return .space
        default:
            return readCharacter(startingWith: byte)
        }
    }

    /// Completes a UTF-8 sequence that began with `first`.
    ///
    /// A non-ASCII key arrives as two to four bytes. Treating each as its own
    /// keystroke turns one letter into several, any of which may land on a
    /// command — typing Cyrillic would quietly trigger quit or delete.
    private func readCharacter(startingWith first: UInt8) -> Key? {
        var bytes = [first]
        let expected = Self.sequenceLength(first)

        while bytes.count < expected {
            var next: UInt8 = 0
            guard read(STDIN_FILENO, &next, 1) == 1 else { break }

            // A byte that is not a continuation starts the next keystroke. It
            // has already been taken from the terminal, so it must be kept:
            // dropping it silently swallows the key that follows.
            guard next & 0b1100_0000 == 0b1000_0000 else {
                pushedBack = next
                break
            }
            bytes.append(next)
        }

        guard let scalar = String(bytes: bytes, encoding: .utf8)?.first else { return nil }
        return .character(scalar)
    }

    /// Byte count of a UTF-8 sequence from its leading byte.
    private static func sequenceLength(_ first: UInt8) -> Int {
        switch first {
        case 0x00 ... 0x7F: 1
        case 0xC0 ... 0xDF: 2
        case 0xE0 ... 0xEF: 3
        case 0xF0 ... 0xF7: 4
        default: 1  // A stray continuation byte; take it alone and move on.
        }
    }

    /// Arrow keys and friends arrive as escape sequences.
    private func readEscapeSequence() -> Key {
        // Escape is both a key and the start of every arrow and mouse report,
        // and nothing in the byte stream distinguishes them. A terminal sends
        // the rest of a sequence immediately, so a brief silence means the key
        // was pressed alone — without this wait, a lone Escape blocks until the
        // next keystroke arrives and then steals it.
        guard waitForInput(timeout: 0.03) else { return .escape }

        var next: UInt8 = 0
        guard read(STDIN_FILENO, &next, 1) == 1 else { return .escape }
        guard next == 0x5B else {
            // ESC O introduces the arrow keys some terminals send in
            // application mode; anything else starts the next keystroke.
            if next == 0x4F { return readApplicationKey() }
            pushedBack = next
            return .escape
        }

        var final: UInt8 = 0
        guard read(STDIN_FILENO, &final, 1) == 1 else { return .escape }

        switch final {
        case 0x41: return .up
        case 0x42: return .down
        case 0x43: return .right
        case 0x44: return .left
        case 0x35: _ = readTrailingTilde(); return .pageUp
        case 0x36: _ = readTrailingTilde(); return .pageDown
        case 0x48: return .home
        case 0x46: return .end
        case 0x3C: return readMouseReport()
        default:
            // An unrecognised sequence still has to be consumed to its final
            // byte. Leaving the rest in the stream turns one scroll of the
            // wheel into a burst of stray keys — including ones that quit.
            discardSequence(startingWith: final)
            return .unknown
        }
    }

    /// Arrow keys in application mode: `ESC O A` and friends.
    private func readApplicationKey() -> Key {
        var final: UInt8 = 0
        guard read(STDIN_FILENO, &final, 1) == 1 else { return .escape }

        switch final {
        case 0x41: return .up
        case 0x42: return .down
        case 0x43: return .right
        case 0x44: return .left
        default: return .unknown
        }
    }

    /// An SGR mouse report: `ESC [ < button ; column ; row M or m`.
    ///
    /// Wheel movement is the part worth acting on; buttons 64 and 65 are scroll
    /// up and down, and everything else is a click this program ignores.
    private func readMouseReport() -> Key {
        var digits: [UInt8] = []
        var byte: UInt8 = 0

        while read(STDIN_FILENO, &byte, 1) == 1 {
            if byte == 0x4D || byte == 0x6D { break }  // 'M' or 'm' ends it.
            digits.append(byte)
        }

        let fields = String(decoding: digits, as: UTF8.self).split(separator: ";")
        guard let button = fields.first.flatMap({ Int($0) }) else { return .unknown }

        switch button {
        case 64: return .scrollUp
        case 65: return .scrollDown
        default: return .unknown
        }
    }

    /// Consumes the remainder of a CSI sequence, which ends at 0x40...0x7E.
    private func discardSequence(startingWith first: UInt8) {
        guard !(0x40 ... 0x7E).contains(first) else { return }

        var byte: UInt8 = 0
        while read(STDIN_FILENO, &byte, 1) == 1 {
            if (0x40 ... 0x7E).contains(byte) { return }
        }
    }

    private func readTrailingTilde() -> Bool {
        var byte: UInt8 = 0
        return read(STDIN_FILENO, &byte, 1) == 1
    }
}

enum Key: Equatable {
    case character(Character)
    case up, down, left, right
    case scrollUp, scrollDown
    case pageUp, pageDown, home, end
    case enter, escape, space, backspace, interrupt

    /// A recognised-but-unhandled sequence, consumed so it cannot be mistaken
    /// for the keys its bytes spell out.
    case unknown
}
