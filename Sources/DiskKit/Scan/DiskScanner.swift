import Foundation

public struct ScanOptions: Sendable {

    /// Visit other volumes mounted inside the tree.
    ///
    /// Off by default so a scan does not wander into external and network
    /// volumes. Note this alone does not prevent double counting on macOS:
    /// firmlinks share a device id with the root, and are excluded by
    /// `deduplicateDirectories` instead.
    public var crossMountPoints: Bool

    /// Count each inode once, so hard-linked files are not summed repeatedly.
    public var deduplicateHardLinks: Bool

    /// Visit each directory inode once.
    ///
    /// macOS firmlinks `/System/Volumes/Data` onto `/`, so the same directories
    /// are reachable by two paths that share a device id — walking both reports
    /// a disk as twice as full as it is. The firmlinked path and its twin are
    /// the same inode, so counting inodes catches it where device ids cannot.
    public var deduplicateDirectories: Bool

    public var concurrency: Int

    public init(
        crossMountPoints: Bool = false,
        deduplicateHardLinks: Bool = true,
        deduplicateDirectories: Bool = true,
        concurrency: Int = ProcessInfo.processInfo.activeProcessorCount * 2
    ) {
        self.crossMountPoints = crossMountPoints
        self.deduplicateHardLinks = deduplicateHardLinks
        self.deduplicateDirectories = deduplicateDirectories
        self.concurrency = concurrency
    }
}

public struct ScanProgress: Sendable {
    public let directories: Int
    public let files: Int
    public let bytes: Int64
    public let current: String
}

/// Walks a directory tree and builds the node tree.
///
/// Work is spread over a fixed pool of threads: the traversal is dominated by
/// blocking syscalls, so threads stay saturated while the kernel reads metadata.
public final class DiskScanner: @unchecked Sendable {

    public let options: ScanOptions
    private let state = State()

    public init(options: ScanOptions = ScanOptions()) {
        self.options = options
    }

    /// Bookkeeping shared by the worker threads.
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var seenInodes: Set<UInt64> = []
        var seenDirectories: Set<UInt64> = []
        var directories = 0
        var files = 0
        var bytes: Int64 = 0
        var current = ""
        var cancelled = false

        /// Returns false when this inode was already counted elsewhere in the tree.
        func claim(inode: UInt64) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return seenInodes.insert(inode).inserted
        }

        /// Returns false when this directory has already been walked by another path.
        func claimDirectory(inode: UInt64) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return seenDirectories.insert(inode).inserted
        }
    }

    public func cancel() {
        state.lock.lock()
        state.cancelled = true
        state.lock.unlock()
    }

    public var progress: ScanProgress {
        state.lock.lock()
        defer { state.lock.unlock() }
        return ScanProgress(
            directories: state.directories,
            files: state.files,
            bytes: state.bytes,
            current: state.current
        )
    }

    public func scan(path: String) -> Node {
        let root = Node(name: normalized(path), kind: .directory)
        let deviceID = options.crossMountPoints ? nil : deviceID(of: path)
        walk(root, deviceID: deviceID)
        return root
    }

    private func walk(_ directory: Node, deviceID: dev_t?) {
        state.lock.lock()
        let cancelled = state.cancelled
        state.directories += 1
        state.current = directory.path
        state.lock.unlock()
        guard !cancelled else { return }

        let entries: [RawEntry]
        do {
            entries = try DirectoryReader.read(path: directory.path)
        } catch {
            directory.error = error.scanError
            return
        }

        var children: [Node] = []
        children.reserveCapacity(entries.count)
        var subdirectories: [Node] = []
        var ownSize: Int64 = 0
        var ownFiles = 0

        for entry in entries {
            switch entry.kind {
            case .directory:
                let child = Node(
                    name: entry.name,
                    kind: .directory,
                    size: entry.allocatedSize,
                    modified: entry.modified,
                    accessed: entry.accessed
                )
                child.parent = directory
                if let deviceID, self.deviceID(of: child.path) != deviceID {
                    continue  // A different volume mounted inside this tree.
                }
                // Skip a directory reachable by two paths, such as a firmlink.
                if options.deduplicateDirectories, !state.claimDirectory(inode: entry.fileID) {
                    continue
                }
                children.append(child)
                subdirectories.append(child)

            case .file, .symlink:
                // A hard-linked file occupies its blocks once, no matter how many
                // names point at it.
                if options.deduplicateHardLinks, entry.linkCount > 1, !state.claim(inode: entry.fileID) {
                    continue
                }
                let child = Node(
                    name: entry.name,
                    kind: entry.kind,
                    size: entry.allocatedSize,
                    fileCount: 1,
                    modified: entry.modified,
                    accessed: entry.accessed
                )
                child.parent = directory
                children.append(child)
                ownSize += entry.allocatedSize
                ownFiles += 1
            }
        }

        state.lock.lock()
        state.files += ownFiles
        state.bytes += ownSize
        state.lock.unlock()

        descend(into: subdirectories, deviceID: deviceID)

        for subdirectory in subdirectories {
            ownSize += subdirectory.size
            ownFiles += subdirectory.fileCount
        }
        ownSize += directory.size  // Blocks of the directory itself, set by the parent.

        directory.children = children.sorted { $0.size > $1.size }
        directory.size = ownSize
        directory.fileCount = ownFiles
    }

    /// Runs the top level of the tree in parallel and deeper levels serially.
    ///
    /// Spawning a task per directory would swamp the pool with millions of tiny
    /// jobs; the fan-out at shallow depth already saturates the available cores.
    private func descend(into subdirectories: [Node], deviceID: dev_t?) {
        guard !subdirectories.isEmpty else { return }

        if subdirectories.count > 1, shouldParallelize(depth: subdirectories[0].depth) {
            DispatchQueue.concurrentPerform(iterations: subdirectories.count) { index in
                walk(subdirectories[index], deviceID: deviceID)
            }
        } else {
            for subdirectory in subdirectories {
                walk(subdirectory, deviceID: deviceID)
            }
        }
    }

    private func shouldParallelize(depth: Int) -> Bool { depth <= 3 }

    private func deviceID(of path: String) -> dev_t? {
        var status = stat()
        guard lstat(path, &status) == 0 else { return nil }
        return status.st_dev
    }

    private func normalized(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }
}
