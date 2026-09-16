import Foundation

/// Brings a saved scan up to date by rescanning only what changed.
///
/// A full scan of a disk takes minutes, almost all of it spent re-measuring
/// directories nothing has touched. The filesystem already knows which paths
/// changed, so the work is proportional to the changes rather than to the disk.
public enum IncrementalScan {

    /// Resolves every symlink in a path, including the ones Foundation keeps.
    static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    public struct Result: Sendable {
        public let snapshot: Snapshot

        /// Directories re-measured.
        public let rescanned: Int

        /// Change in total size since the previous scan.
        public let delta: Int64

        /// Set when the journal could not be used and a full scan was done.
        public let fellBackToFullScan: ChangeJournal.Outcome.Reason?
    }

    /// Updates `snapshot` in place of rescanning everything.
    ///
    /// Falls back to a full scan when the journal cannot answer — too much has
    /// changed, events were dropped, or the snapshot predates the tracking.
    public static func update(
        _ snapshot: Snapshot,
        options: ScanOptions = ScanOptions(),
        journalLimit: Int = 20_000
    ) -> Result {
        let root = snapshot.rootPath
        let outcome = ChangeJournal.changes(
            under: root, since: snapshot.journalPosition, limit: journalLimit
        )

        guard case .changed(let changedPaths) = outcome else {
            guard case .unusable(let reason) = outcome else {
                return fullScan(root: root, options: options, reason: .unavailable)
            }
            return fullScan(root: root, options: options, reason: reason)
        }

        let position = ChangeJournal.currentPosition()
        let previousSize = snapshot.totalSize

        // FSEvents reports fully resolved paths while the tree holds the path
        // as given, so /var/folders and /private/var/folders must be reconciled
        // before anything can be looked up.
        let realRoot = realPath(root)
        let targets = topmost(changedPaths).map { path -> String in
            guard realRoot != root, path.hasPrefix(realRoot) else { return path }
            return root + String(path.dropFirst(realRoot.count))
        }

        var rescanned = 0
        let scanner = DiskScanner(options: options)

        for path in targets {
            guard let node = snapshot.root.node(atPath: path) ?? nearestExisting(path, in: snapshot.root)
            else { continue }
            guard replace(node, using: scanner, in: snapshot.root) else { continue }
            rescanned += 1
        }

        return Result(
            snapshot: Snapshot(
                root: snapshot.root,
                rootPath: root,
                scannedAt: Date(),
                options: options,
                duration: snapshot.duration,
                volume: VolumeInfo(path: root),
                journalPosition: position
            ),
            rescanned: rescanned,
            delta: snapshot.root.size - previousSize,
            fellBackToFullScan: nil
        )
    }

    // MARK: - Rescanning one directory

    /// Re-measures `node` and corrects every ancestor's totals by the difference.
    private static func replace(_ node: Node, using scanner: DiskScanner, in root: Node) -> Bool {
        let path = node.path

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            // Deleted since the scan: drop it and take its size off its ancestors.
            detach(node)
            return true
        }
        guard isDirectory.boolValue else {
            return refreshFile(node)
        }

        let fresh = scanner.scan(path: path)
        let sizeDelta = fresh.size - node.size
        let fileDelta = fresh.fileCount - node.fileCount

        node.children = fresh.children
        for child in node.children { child.parent = node }
        node.size = fresh.size
        node.fileCount = fresh.fileCount
        node.modified = fresh.modified
        node.accessed = fresh.accessed
        node.error = fresh.error

        propagate(sizeDelta: sizeDelta, fileDelta: fileDelta, from: node)
        return true
    }

    private static func refreshFile(_ node: Node) -> Bool {
        var status = stat()
        guard lstat(node.path, &status) == 0 else { return false }

        let size = Int64(status.st_blocks) * 512
        propagate(sizeDelta: size - node.size, fileDelta: 0, from: node)
        node.size = size
        node.modified = Date(timeIntervalSince1970: Double(status.st_mtimespec.tv_sec))
        node.accessed = Date(timeIntervalSince1970: Double(status.st_atimespec.tv_sec))
        return true
    }

    private static func detach(_ node: Node) {
        guard let parent = node.parent else { return }
        parent.children.removeAll { $0 === node }
        propagate(sizeDelta: -node.size, fileDelta: -node.fileCount, from: parent)
    }

    /// Applies a change in size to every ancestor, so totals stay consistent.
    private static func propagate(sizeDelta: Int64, fileDelta: Int, from node: Node) {
        guard sizeDelta != 0 || fileDelta != 0 else { return }
        var ancestor = node.parent
        while let current = ancestor {
            current.size += sizeDelta
            current.fileCount += fileDelta
            ancestor = current.parent
        }
    }

    // MARK: - Choosing what to rescan

    /// Drops paths already covered by another, so a subtree is scanned once.
    static func topmost(_ paths: Set<String>) -> [String] {
        let sorted = paths.sorted()
        var result: [String] = []

        for path in sorted {
            if let last = result.last, path == last || path.hasPrefix(last + "/") { continue }
            result.append(path)
        }
        return result
    }

    /// The closest ancestor of `path` present in the tree.
    ///
    /// A newly created directory has no node yet, so its parent is rescanned.
    private static func nearestExisting(_ path: String, in root: Node) -> Node? {
        var candidate = (path as NSString).deletingLastPathComponent
        while candidate.count > 1 {
            if let node = root.node(atPath: candidate) { return node }
            candidate = (candidate as NSString).deletingLastPathComponent
        }
        return root.node(atPath: "/")
    }

    private static func fullScan(
        root: String,
        options: ScanOptions,
        reason: ChangeJournal.Outcome.Reason
    ) -> Result {
        let position = ChangeJournal.currentPosition()
        let scanner = DiskScanner(options: options)
        let started = Date()
        let tree = scanner.scan(path: root)

        return Result(
            snapshot: Snapshot(
                root: tree,
                rootPath: root,
                options: options,
                duration: Date().timeIntervalSince(started),
                volume: VolumeInfo(path: root),
                journalPosition: position
            ),
            rescanned: 1,
            delta: 0,
            fellBackToFullScan: reason
        )
    }
}
