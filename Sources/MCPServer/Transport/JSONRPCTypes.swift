// Sources/MCPServer/Transport/JSONRPCTypes.swift
// 参照: docs/architecture/MCP_SERVER.md - JSON-RPC通信

import Foundation

// MARK: - JSON-RPC Request

/// JSON-RPCリクエスト
public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: RequestID?
    public let method: String
    public let params: [String: AnyCodable]?

    public init(jsonrpc: String = "2.0", id: RequestID? = nil, method: String, params: [String: AnyCodable]? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }
}

/// リクエストIDの型（intまたはstring）
public enum RequestID: Codable, Equatable, Sendable {
    case int(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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
public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: RequestID?
    public let result: AnyCodable?
    public let error: JSONRPCError?

    public init(id: RequestID?, result: Any) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = AnyCodable(result)
        self.error = nil
    }

    public init(id: RequestID?, error: JSONRPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

/// JSON-RPCエラー
public struct JSONRPCError: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: AnyCodable?

    public init(code: Int, message: String, data: Any? = nil) {
        self.code = code
        self.message = message
        self.data = data.map { AnyCodable($0) }
    }

    // 標準エラーコード
    public static let parseError = JSONRPCError(code: -32700, message: "Parse error")
    public static let invalidRequest = JSONRPCError(code: -32600, message: "Invalid Request")
    public static let methodNotFound = JSONRPCError(code: -32601, message: "Method not found")
    public static let invalidParams = JSONRPCError(code: -32602, message: "Invalid params")
    public static let internalError = JSONRPCError(code: -32603, message: "Internal error")
}

// MARK: - AnyCodable

/// 任意のCodable値をラップするヘルパー
/// JSONシリアライズ可能な値（文字列、数値、Bool、配列、辞書、null）のみを扱うため
/// @unchecked Sendableを使用（JSONデータは作成後イミュータブル）
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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

public extension AnyCodable {
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
