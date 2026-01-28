// Sources/MCPServer/Transport/Transport.swift
// トランスポート層の抽象インターフェース
// 参照: docs/architecture/MCP_SERVER.md

import Foundation
import Infrastructure

/// MCPトランスポート層のプロトコル
/// stdio（Claude Code用）とUnixソケット（Runner用）の両方をサポート
protocol MCPTransport {
    /// メッセージを読み取る
    func readMessage() throws -> JSONRPCRequest

    /// メッセージを書き込む
    func writeMessage(_ response: JSONRPCResponse) throws

    /// ログを出力
    func log(_ message: String)
}

// MARK: - TransportError

/// トランスポート層で発生するエラー
enum TransportError: Error, CustomStringConvertible {
    case invalidHeader(String)
    case invalidContentLength(String)
    case incompleteRead
    case endOfInput
    case invalidJSON(Error)
    case encodingFailed

    var description: String {
        switch self {
        case .invalidHeader(let header):
            return "Invalid header: \(header)"
        case .invalidContentLength(let value):
            return "Invalid Content-Length: \(value)"
        case .incompleteRead:
            return "Incomplete read"
        case .endOfInput:
            return "End of input"
        case .invalidJSON(let error):
            return "Invalid JSON: \(error)"
        case .encodingFailed:
            return "Encoding failed"
        }
    }
}

// MARK: - NullTransport (HTTP用)

/// HTTPトランスポート用のダミートランスポート
/// HTTPモードではread/writeは使用されず、processHTTPRequestで直接処理される
/// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ1.2
final class NullTransport: MCPTransport {
    func readMessage() throws -> JSONRPCRequest {
        throw TransportError.endOfInput
    }

    func writeMessage(_ response: JSONRPCResponse) throws {
        // HTTP mode uses direct request/response, not transport
    }

    func log(_ message: String) {
        // MCPLoggerに委譲（transport カテゴリで出力）
        MCPLogger.shared.debug("[HTTP] \(message)", category: .transport)
    }
}
