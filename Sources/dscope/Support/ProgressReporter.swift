import DiskKit
import Foundation

/// Prints scan progress to stderr while a scan runs.
///
/// A full-disk scan takes minutes; without this the tool looks hung. Output
/// goes to stderr and is suppressed when stderr is not a terminal, so piped
/// and JSON output stay clean.
final class ProgressReporter {

    private let scanner: DiskScanner
    private let interval: TimeInterval
    private let estimate: ScanEstimate?
    private let state = State()

    init(scanner: DiskScanner, estimate: ScanEstimate? = nil, interval: TimeInterval = 0.08) {
        self.scanner = scanner
        self.estimate = estimate
        self.interval = interval
    }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        let stopped = DispatchSemaphore(value: 0)
        var isFinished = false
        var frame = 0

        func next() -> Int? {
            lock.lock()
            defer { lock.unlock() }
            guard !isFinished else { return nil }
            frame += 1
            return frame
        }

        func finish() {
            lock.lock()
            isFinished = true
            lock.unlock()
        }

        func awaitExit(timeout: TimeInterval) {
            _ = stopped.wait(timeout: .now() + timeout)
        }

        func signalExit() {
            stopped.signal()
        }
    }

    static var isSupported: Bool {
        isatty(STDERR_FILENO) == 1
    }

    func start() {
        guard Self.isSupported else {
            state.signalExit()
            return
        }
        hideCursor()
        let thread = Thread { [weak self] in self?.loop() }
        thread.qualityOfService = .utility
        thread.start()
    }

    func stop() {
        state.finish()
        guard Self.isSupported else { return }

        // Wait for the drawing thread to notice: anything it writes after this
        // returns lands on whatever the caller draws next, such as a TUI frame.
        state.awaitExit(timeout: 1)
        write(clearLine)
        showCursor()
    }

    private func loop() {
        defer { state.signalExit() }
        while let frame = state.next() {
            render(frame: frame)
            Thread.sleep(forTimeInterval: interval)
        }
    }

    private func render(frame: Int) {
        let progress = scanner.progress
        let spinner = Self.spinnerFrames[frame % Self.spinnerFrames.count]

        // "15 GB / 494 GB" rather than a bare percentage: the denominator is an
        // estimate, and showing it says where the number comes from. Without one
        // the total reads "?", which is the honest answer — the size of a tree
        // is not knowable until it has been walked.
        var counts: String
        if let estimate {
            let fraction = estimate.fraction(scanned: progress.bytes)
            counts = "\(bar(fraction)) \(progress.bytes.formattedBytes()) / \(estimate.totalBytes.formattedBytes())"
        } else {
            counts = "\(progress.bytes.formattedBytes()) / ?"
        }
        counts += "  \(formatted(progress.files)) files"

        let path = shorten(progress.current, reserving: counts.count + 4)

        // Dim everything: a bright full-width line reads like editable input
        // rather than a status that is about to be erased.
        write(clearLine + dim("\(spinner) \(counts)  \(path)"))
    }

    private func bar(_ fraction: Double) -> String {
        let width = 12
        let filled = Int((fraction * Double(width)).rounded())
        return String(repeating: "━", count: filled) + String(repeating: "─", count: width - filled)
    }

    private static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    private let clearLine = "\u{1B}[2K\r"

    private func dim(_ text: String) -> String {
        "\u{1B}[2m" + text + "\u{1B}[0m"
    }

    private func hideCursor() { write("\u{1B}[?25l") }
    private func showCursor() { write("\u{1B}[?25h") }

    private func write(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }

    /// Counts run to millions, so they are abbreviated once they get long.
    private func formatted(_ count: Int) -> String {
        switch count {
        case ..<10_000:
            return String(count)
        case ..<1_000_000:
            return "\(count / 1000)k"
        default:
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
    }

    /// Keeps the line inside the terminal width so it never wraps and scrolls.
    private func shorten(_ path: String, reserving used: Int) -> String {
        var width = 80
        var size = winsize()
        if ioctl(STDERR_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 {
            width = Int(size.ws_col)
        }
        let budget = max(12, width - used - 2)
        guard path.count > budget else { return path }
        return "…" + String(path.suffix(budget - 1))
    }
}
