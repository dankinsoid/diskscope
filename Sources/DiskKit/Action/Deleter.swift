import Foundation

public enum DeletionMethod: String, Sendable, CaseIterable {
    /// Hand the item to the Finder's Trash, so the system owns undo.
    case trash
    /// Unlink immediately. Frees space at once, but nothing can be recovered.
    case permanent
}

public struct DeletionOutcome: Sendable {
    public let path: String
    public let bytes: Int64
    public let error: String?

    public var succeeded: Bool { error == nil }
}

public struct DeletionSummary: Sendable {
    public let outcomes: [DeletionOutcome]

    public var freedBytes: Int64 {
        outcomes.filter(\.succeeded).reduce(0) { $0 + $1.bytes }
    }
    public var failures: [DeletionOutcome] { outcomes.filter { !$0.succeeded } }
    public var deletedCount: Int { outcomes.count(where: \.succeeded) }
}

/// Removes selected entries.
///
/// Paths are re-checked against the filesystem before anything is removed: a
/// snapshot may be hours old, and acting on a stale path is how the wrong thing
/// gets deleted.
public struct Deleter: Sendable {

    public let method: DeletionMethod
    public let protectedPrefixes: [String]

    /// Locations that must never be deleted through this tool, whatever a
    /// snapshot or an agent suggests.
    public static let defaultProtectedPrefixes = [
        "/System",
        "/bin",
        "/sbin",
        "/usr/bin",
        "/usr/sbin",
        "/usr/lib",
        "/Library/Apple",
        "/Volumes/Preboot",
        "/private/var/db",
    ]

    public init(method: DeletionMethod = .trash, protectedPrefixes: [String] = Deleter.defaultProtectedPrefixes) {
        self.method = method
        self.protectedPrefixes = protectedPrefixes
    }

    public func isProtected(_ path: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        if standardized == "/" || standardized.isEmpty { return true }

        // The home directory itself is a plausible selection and a catastrophic one.
        if standardized == NSHomeDirectory() { return true }

        return protectedPrefixes.contains { standardized == $0 || standardized.hasPrefix($0 + "/") }
    }

    /// Validates a path without touching it.
    public func check(_ path: String) -> DeletionRefusal? {
        if isProtected(path) { return .protected }
        guard FileManager.default.fileExists(atPath: path) else { return .missing }
        return nil
    }

    public func delete(paths: [String], sizes: [String: Int64] = [:]) -> DeletionSummary {
        var outcomes: [DeletionOutcome] = []

        for path in paths {
            let bytes = sizes[path] ?? 0

            if let refusal = check(path) {
                outcomes.append(DeletionOutcome(path: path, bytes: bytes, error: refusal.description))
                continue
            }

            do {
                let url = URL(fileURLWithPath: path)
                switch method {
                case .trash:
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                case .permanent:
                    try FileManager.default.removeItem(at: url)
                }
                outcomes.append(DeletionOutcome(path: path, bytes: bytes, error: nil))
            } catch {
                outcomes.append(
                    DeletionOutcome(path: path, bytes: bytes, error: error.localizedDescription)
                )
            }
        }
        return DeletionSummary(outcomes: outcomes)
    }
}

public enum DeletionRefusal: Sendable, CustomStringConvertible {
    case protected
    case missing

    public var description: String {
        switch self {
        case .protected: "refused: protected system location"
        case .missing: "no longer exists"
        }
    }
}
