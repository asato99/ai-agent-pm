// Sources/MCPServer/Transport/Transport.swift
// トランスポート層の抽象インターフェース
// 参照: docs/architecture/MCP_SERVER.md

import Foundation

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
