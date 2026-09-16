import DiskKit
import Foundation

/// An MCP server exposing the same capabilities as the `dscope` CLI.
///
/// Deliberately read-only: an agent may measure and plan, but deleting stays
/// with the person, who runs `dscope clean --apply` after seeing the paths.
let server = Server()
server.run()

final class Server {

    private var snapshots: [String: Snapshot] = [:]

    func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }

            guard let request = try? JSONDecoder().decode(JSONRPC.Request.self, from: data) else {
                JSONRPC.respond(id: nil, code: -32700, message: "parse error")
                continue
            }
            handle(request)
        }
    }

    private func handle(_ request: JSONRPC.Request) {
        switch request.method {
        case "initialize":
            JSONRPC.respond(id: request.id, result: InitializeResult())

        case "tools/list":
            JSONRPC.respond(id: request.id, result: ToolsListResult(tools: Tools.all))

        case "tools/call":
            call(request)

        case "notifications/initialized", "notifications/cancelled":
            break  // Notifications carry no id and take no reply.

        default:
            guard request.id != nil else { break }
            JSONRPC.respond(id: request.id, code: -32601, message: "unknown method '\(request.method)'")
        }
    }

    private func call(_ request: JSONRPC.Request) {
        guard let name = request.params?["name"]?.stringValue else {
            JSONRPC.respond(id: request.id, code: -32602, message: "missing tool name")
            return
        }
        let arguments = request.params?["arguments"] ?? .null

        do {
            let text = try Tools.run(name: name, arguments: arguments, snapshots: &snapshots)
            JSONRPC.respond(id: request.id, result: ToolCallResult(text: text))
        } catch {
            // Reported as a tool result, not a protocol error: the model should
            // see what went wrong and adjust.
            JSONRPC.respond(id: request.id, result: ToolCallResult(text: "Error: \(error)", isError: true))
        }
    }
}

struct InitializeResult: Encodable {
    struct Capabilities: Encodable {
        struct Tools: Encodable { let listChanged = false }
        let tools = Tools()
    }
    struct ServerInfo: Encodable {
        let name = "diskscope"
        let version = "0.1.0"
    }

    let protocolVersion = "2024-11-05"
    let capabilities = Capabilities()
    let serverInfo = ServerInfo()
}

struct ToolsListResult: Encodable {
    let tools: [ToolDefinition]
}

struct ToolCallResult: Encodable {
    struct Content: Encodable {
        let type = "text"
        let text: String
    }

    let content: [Content]
    let isError: Bool?

    init(text: String, isError: Bool = false) {
        self.content = [Content(text: text)]
        self.isError = isError ? true : nil
    }
}
