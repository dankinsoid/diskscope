import DiskKit
import Foundation

enum Output {

    static func emit(_ value: some Encodable, pretty: Bool) throws {
        let data = try JSONEncoder.reportEncoder(pretty: pretty).encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func note(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

/// Draws the tree the way `tree(1)` does, with sizes in a leading column.
enum TreeRenderer {

    static func render(
        _ node: Node,
        depth: Int,
        minimumSize: Int64,
        selection: Selection? = nil
    ) -> String {
        var lines: [String] = ["\(node.size.formattedBytes())\t\(node.path)"]
        append(children: node, prefix: "", depth: depth, minimumSize: minimumSize, selection: selection, into: &lines)
        return lines.joined(separator: "\n")
    }

    private static func append(
        children parent: Node,
        prefix: String,
        depth: Int,
        minimumSize: Int64,
        selection: Selection?,
        into lines: inout [String]
    ) {
        guard depth > 0 else { return }
        let visible = parent.children.filter { $0.size >= minimumSize }

        for (index, child) in visible.enumerated() {
            let isLast = index == visible.count - 1
            let branch = isLast ? "└── " : "├── "
            let marker = selection?.covers(child) == true ? "[x] " : ""
            let suffix = child.error != nil ? "  (unreadable)" : ""
            let name = child.isDirectory ? child.name + "/" : child.name

            lines.append("\(child.size.formattedBytes())\t\(prefix)\(branch)\(marker)\(name)\(suffix)")

            if child.isDirectory {
                append(
                    children: child,
                    prefix: prefix + (isLast ? "    " : "│   "),
                    depth: depth - 1,
                    minimumSize: minimumSize,
                    selection: selection,
                    into: &lines
                )
            }
        }
    }
}
