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
    private var thread: Thread?
    private let finished = NSLock()
    private var isFinished = false

    init(scanner: DiskScanner, interval: TimeInterval = 0.1) {
        self.scanner = scanner
        self.interval = interval
    }

    static var isSupported: Bool {
        isatty(STDERR_FILENO) == 1
    }

    func start() {
        guard Self.isSupported else { return }
        let thread = Thread { [weak self] in self?.loop() }
        thread.qualityOfService = .utility
        self.thread = thread
        thread.start()
    }

    func stop() {
        finished.lock()
        isFinished = true
        finished.unlock()
        guard Self.isSupported else { return }
        clearLine()
    }

    private func loop() {
        while true {
            finished.lock()
            let done = isFinished
            finished.unlock()
            if done { return }

            let progress = scanner.progress
            let line = "  \(progress.bytes.formattedBytes())  \(progress.files) files  \(shorten(progress.current))"
            FileHandle.standardError.write(Data(("\u{1B}[2K\r" + line).utf8))
            Thread.sleep(forTimeInterval: interval)
        }
    }

    private func clearLine() {
        FileHandle.standardError.write(Data("\u{1B}[2K\r".utf8))
    }

    /// Keeps the line inside the terminal width so it does not wrap and scroll.
    private func shorten(_ path: String) -> String {
        var width = 80
        var size = winsize()
        if ioctl(STDERR_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 {
            width = Int(size.ws_col)
        }
        let budget = max(20, width - 40)
        guard path.count > budget else { return path }
        return "…" + String(path.suffix(budget - 1))
    }
}
