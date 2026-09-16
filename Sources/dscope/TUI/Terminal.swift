import Foundation

/// Raw-mode terminal control: keys arrive unbuffered, output is drawn in place.
final class Terminal {

    private var original = termios()
    private(set) var isActive = false

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
        raw.c_lflag &= ~(UInt(ECHO) | UInt(ICANON) | UInt(ISIG) | UInt(IEXTEN))
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
        isActive = true
    }

    func deactivate() {
        guard isActive else { return }
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
        for line in lines {
            output += "\u{1B}[2K" + line + "\r\n"
        }
        output += "\u{1B}[J"  // Erase anything left below a shorter frame.
        write(output)
    }

    /// Whether more input is already waiting, so a burst can be drained before
    /// redrawing. Typing arrives faster than a search over a large tree can run.
    func hasPendingInput() -> Bool {
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        return poll(&descriptor, 1, 0) > 0
    }

    /// Blocks until a key is pressed.
    func readKey() -> Key? {
        var byte: UInt8 = 0
        guard read(STDIN_FILENO, &byte, 1) == 1 else { return nil }

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
            return .character(Character(UnicodeScalar(byte)))
        }
    }

    /// Arrow keys and friends arrive as escape sequences.
    private func readEscapeSequence() -> Key {
        var next: UInt8 = 0
        // A lone Escape is a key in its own right; anything else is a sequence.
        guard read(STDIN_FILENO, &next, 1) == 1, next == 0x5B else { return .escape }

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
        default: return .escape
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
    case pageUp, pageDown, home, end
    case enter, escape, space, backspace, interrupt
}
