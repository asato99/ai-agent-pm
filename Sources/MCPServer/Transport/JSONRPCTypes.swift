// Sources/MCPServer/Transport/JSONRPCTypes.swift
// 参照: docs/architecture/MCP_SERVER.md - JSON-RPC通信

import Foundation

// MARK: - JSON-RPC Request

/// JSON-RPCリクエスト
struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: RequestID?
    let method: String
    let params: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }
}

/// リクエストIDの型（intまたはstring）
enum RequestID: Codable, Equatable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                RequestID.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Int or String")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

// MARK: - JSON-RPC Response

/// JSON-RPCレスポンス
struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: RequestID?
    let result: AnyCodable?
    let error: JSONRPCError?

    init(id: RequestID?, result: Any) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = AnyCodable(result)
        self.error = nil
    }

    init(id: RequestID?, error: JSONRPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

/// JSON-RPCエラー
struct JSONRPCError: Codable {
    let code: Int
    let message: String
    let data: AnyCodable?

    init(code: Int, message: String, data: Any? = nil) {
        self.code = code
        self.message = message
        self.data = data.map { AnyCodable($0) }
    }

    // 標準エラーコード
    static let parseError = JSONRPCError(code: -32700, message: "Parse error")
    static let invalidRequest = JSONRPCError(code: -32600, message: "Invalid Request")
    static let methodNotFound = JSONRPCError(code: -32601, message: "Method not found")
    static let invalidParams = JSONRPCError(code: -32602, message: "Invalid params")
    static let internalError = JSONRPCError(code: -32603, message: "Internal error")
}

// MARK: - AnyCodable

/// 任意のCodable値をラップするヘルパー
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable cannot decode value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            let context = EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "AnyCodable cannot encode value of type \(type(of: value))"
            )
            throw EncodingError.invalidValue(value, context)
        }
    }
}

// MARK: - AnyCodable Helpers

extension AnyCodable {
    /// 文字列として取得
    var stringValue: String? {
        value as? String
    }

    /// 整数として取得
    var intValue: Int? {
        value as? Int
    }

    /// 辞書として取得
    var dictionaryValue: [String: Any]? {
        value as? [String: Any]
    }

    /// 配列として取得
    var arrayValue: [Any]? {
        value as? [Any]
    }
}
