import Foundation

/// Minimal JSON-RPC 2.0 over stdio, which is all the MCP stdio transport is.
///
/// Written by hand rather than pulled from an SDK: the surface used here is a
/// handful of methods, and a dependency would outweigh it.
enum JSONRPC {

    struct Request: Decodable {
        let jsonrpc: String
        let id: ID?
        let method: String
        let params: JSONValue?
    }

    /// An id may be a number or a string, and must be echoed back unchanged.
    enum ID: Codable, Sendable {
        case number(Int)
        case string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Int.self) {
                self = .number(value)
            } else {
                self = .string(try container.decode(String.self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .number(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            }
        }
    }

    struct ErrorPayload: Encodable {
        let code: Int
        let message: String
    }

    static func respond(id: ID?, result: some Encodable) {
        send(Response(id: id, result: AnyEncodable(result), error: nil))
    }

    static func respond(id: ID?, code: Int, message: String) {
        send(Response(id: id, result: nil, error: ErrorPayload(code: code, message: message)))
    }

    private struct Response: Encodable {
        let jsonrpc = "2.0"
        let id: ID?
        let result: AnyEncodable?
        let error: ErrorPayload?
    }

    private static func send(_ response: some Encodable) {
        guard let data = try? JSONEncoder.reportEncoderForRPC().encode(response) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void

    init(_ value: some Encodable) {
        encode = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}

/// Just enough of a JSON value to read tool arguments.
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .number(let value) = self { return Int(value) }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let dictionary) = self { return dictionary[key] }
        return nil
    }
}

extension JSONEncoder {

    static func reportEncoderForRPC() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }
}
