import CoreServices
import Foundation

/// Reads the filesystem's own record of what changed since a scan.
///
/// A directory's `mtime` only moves when its immediate children change, so it
/// cannot tell whether anything deep inside was touched. FSEvents can: macOS
/// keeps a journal of changed paths, and a scan that records the journal
/// position can later ask what has happened since.
public enum ChangeJournal {

    /// The journal position now, to be stored with a scan.
    public static func currentPosition() -> UInt64 {
        FSEventsGetCurrentEventId()
    }

    public enum Outcome: Sendable {
        /// Paths whose contents changed. Their common directories are enough to
        /// rescan; files under them need not be listed individually.
        case changed(directories: Set<String>)

        /// The journal could not answer, so nothing short of a full scan is safe.
        case unusable(reason: Reason)

        public enum Reason: String, Sendable {
            case noPosition = "the snapshot predates change tracking"
            case tooOld = "too much has changed since the snapshot"
            case dropped = "the system dropped events"
            case unavailable = "the change journal is unavailable"
        }
    }

    /// Directories changed under `root` since `position`.
    ///
    /// - Parameter limit: give up beyond this many events, since replaying a
    ///   long history costs more than rescanning.
    public static func changes(
        under root: String,
        since position: UInt64,
        limit: Int = 20_000,
        timeout: TimeInterval = 10
    ) -> Outcome {
        guard position > 0 else { return .unusable(reason: .noPosition) }

        // FSEvents reports real paths, so /tmp arrives as /private/tmp and a
        // prefix test against the unresolved path would silently match nothing.
        // Foundation's resolvingSymlinksInPath leaves /tmp alone, so ask libc.
        let resolved = realPath(root)
        let collector = Collector(root: resolved, limit: limit)

        // The stream outlives this scope on its own queue, so the collector is
        // retained for the callback and released once the stream is gone.
        let retained = Unmanaged.passRetained(collector)
        defer { retained.release() }

        var context = FSEventStreamContext(
            version: 0,
            info: retained.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let paths = [resolved] as CFArray
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, paths, flags, _ in
                guard let info else { return }
                let collector = Unmanaged<Collector>.fromOpaque(info).takeUnretainedValue()
                collector.absorb(count: count, paths: paths, flags: flags)
            },
            &context,
            paths,
            position,
            0.1,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
        ) else {
            return .unusable(reason: .unavailable)
        }

        let queue = DispatchQueue(label: "diskscope.change-journal")
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return .unusable(reason: .unavailable)
        }

        let finished = collector.waitForHistory(timeout: timeout)

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)

        if let reason = collector.failure { return .unusable(reason: reason) }
        guard finished else { return .unusable(reason: .tooOld) }
        return .changed(directories: collector.directories)
    }
}

/// Resolves every symlink in a path, including the ones Foundation keeps.
private func realPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
}

/// Accumulates changed directories from the FSEvents callback.
private final class Collector: @unchecked Sendable {

    private let root: String
    private let limit: Int
    private let lock = NSLock()
    private let historyDone = DispatchSemaphore(value: 0)

    private(set) var directories: Set<String> = []
    private(set) var failure: ChangeJournal.Outcome.Reason?

    init(root: String, limit: Int) {
        self.root = root
        self.limit = limit
    }

    func waitForHistory(timeout: TimeInterval) -> Bool {
        historyDone.wait(timeout: .now() + timeout) == .success
    }

    func absorb(
        count: Int,
        paths: UnsafeMutableRawPointer,
        flags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        // Without kFSEventStreamCreateFlagUseCFTypes the callback receives a
        // C array of C strings, not a CFArray.
        let cPaths = paths.bindMemory(to: UnsafePointer<CChar>?.self, capacity: count)

        lock.lock()
        defer { lock.unlock() }

        for index in 0 ..< count {
            let flag = Int(flags[index])

            if flag & kFSEventStreamEventFlagHistoryDone != 0 {
                historyDone.signal()
                return
            }
            if flag & (kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped) != 0 {
                failure = .dropped
                historyDone.signal()
                return
            }
            // The root itself moved or was replaced; nothing below can be trusted.
            if flag & kFSEventStreamEventFlagRootChanged != 0 {
                failure = .tooOld
                historyDone.signal()
                return
            }

            guard let cPath = cPaths[index] else { continue }
            var path = String(cString: cPath)
            if path.count > 1, path.hasSuffix("/") { path.removeLast() }
            guard path == root || path.hasPrefix(root == "/" ? "/" : root + "/") else { continue }

            // Without FileEvents the path is already the directory that changed.
            directories.insert(path)

            if directories.count > limit {
                failure = .tooOld
                historyDone.signal()
                return
            }
        }
    }
}
